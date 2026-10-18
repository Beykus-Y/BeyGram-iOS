package com.beykus.beygram.data.vpn

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.beykus.beygram.R
import com.beykus.beygram.domain.UiText
import com.beykus.beygram.domain.UserMessageException
import com.beykus.beygram.domain.model.MihomoConnection
import com.beykus.beygram.domain.model.MihomoProbeResult
import com.beykus.beygram.domain.model.TelegramConnectionState
import com.beykus.beygram.domain.model.VpnNetworkState
import com.beykus.beygram.domain.model.VpnSettings
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.atomic.AtomicInteger

/**
 * The VPN/proxy controller of the process. It is created once with the application scope, so the proxy
 * and its automatic selection keep working when no screen is shown.
 */
internal class VpnBackend private constructor(
    context: Context,
    connectionState: StateFlow<TelegramConnectionState>,
    private val scope: CoroutineScope,
    private val setTdLibProxy: suspend (Boolean) -> Result<Unit>,
    private val isTdLibProxyEnabled: suspend () -> Result<Boolean>
) {
    private val appContext = context.applicationContext
    private val settingsStore = VpnSettingsStore(appContext)
    private val installationHwid = InstallationHwidProvider(appContext)
    private val subscriptionClient = SubscriptionClient(installationHwid)
    private val mihomo = MihomoCoreBridge(appContext)
    private val networkMonitor = VpnNetworkMonitor(appContext)
    private val selector = TelegramAutoSelector(
        scope = scope,
        connectionState = connectionState,
        networkState = networkMonitor.state,
        settings = settingsStore.settings,
        runtimeState = MihomoProxyService.runtimeState,
        mihomo = mihomo,
        report = { event ->
            _autoSelectEvents.value = event
            if (event is AutoSelectEvent.Switched) checkSelectedRoute()
        }
    )

    val settings: StateFlow<VpnSettings> = settingsStore.settings
    val network: StateFlow<VpnNetworkState> = networkMonitor.state
    val runtimeState: StateFlow<ProxyRuntimeState> = MihomoProxyService.runtimeState
    private val _connections = MutableStateFlow<List<MihomoConnection>>(emptyList())
    val connections: StateFlow<List<MihomoConnection>> = _connections.asStateFlow()
    private val _probes = MutableStateFlow<Map<String, MihomoProbeResult>>(emptyMap())
    val probes: StateFlow<Map<String, MihomoProbeResult>> = _probes.asStateFlow()
    private val _autoSelectEvents = MutableStateFlow<AutoSelectEvent?>(null)
    val autoSelectEvents: StateFlow<AutoSelectEvent?> = _autoSelectEvents.asStateFlow()
    private val routeProbeGeneration = AtomicInteger()
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()
    private val _probeProgress = MutableStateFlow<ProbeProgress?>(null)
    val probeProgress: StateFlow<ProbeProgress?> = _probeProgress.asStateFlow()

    private val restoreMutex = Mutex()
    private val _restoreFailed = MutableStateFlow(false)
    /** True when the automatic restore failed on every try. The user then decides: try again or turn the proxy off. */
    val restoreFailed: StateFlow<Boolean> = _restoreFailed.asStateFlow()
    private val _restoreRetrying = MutableStateFlow(false)
    /** True while a retry that the user asked for runs. The dialog then shows a hint instead of the question. */
    val restoreRetrying: StateFlow<Boolean> = _restoreRetrying.asStateFlow()

    init {
        networkMonitor.start()
        selector.start()
        // TDLib connectivity belongs to its own metric, not to listener or testDelay health.
        scope.launch {
            var previouslyConnected = false
            connectionState.collect { state ->
                val connected = state == TelegramConnectionState.Connected
                MihomoProxyService.reportTelegramConnection(connected)
                // Only the enum is logged; never include endpoints, subscription keys or messages.
                MihomoRuntimeDiagnostics.event("tdlib", "connection_state=${state.name}")
                // Re-check only on a meaningful connectivity loss, never with periodic polling.
                if (previouslyConnected && !connected && runtimeState.value.status == ProxyRuntimeStatus.RUNNING) {
                    checkSelectedRoute()
                }
                previouslyConnected = connected
            }
        }
        scope.launch {
            // The connection flow may already be Connected before the listener reaches RUNNING.
            // Reconcile its current value on start/restart, even if TDLib emits no new state.
            runtimeState.collect { proxy ->
                if (proxy.status == ProxyRuntimeStatus.RUNNING) {
                    MihomoProxyService.reportTelegramConnection(connectionState.value == TelegramConnectionState.Connected)
                }
            }
        }
        scope.launch(Dispatchers.IO) { restore() }
    }

    /**
     * Called when an app screen opens, and when the user asks again after the automatic restore failed. It starts a
     * fresh round of attempts, unless a round is already running and will report the result.
     */
    suspend fun restoreFromScreen() {
        if (restoreMutex.isLocked) return
        restore()
    }

    /** Called when the user taps Retry in the restore dialog. The dialog shows a hint while this round runs. */
    suspend fun retryRestore() {
        if (restoreMutex.isLocked) return
        _restoreRetrying.value = true
        try {
            restore()
            // restore() can return while a start or stop from elsewhere is still running. The question waits for that result,
            // so a proxy that comes up is not reported as failed. There is no timeout: the hint stays until the state settles,
            // and turning the proxy off stays available.
            val state = runtimeState.first { it.status != ProxyRuntimeStatus.STARTING && it.status != ProxyRuntimeStatus.STOPPING }
            // The question comes back only when the proxy stopped or failed, and TDLib does not say it is off.
            val stoppedOrFailed = state.status == ProxyRuntimeStatus.STOPPED || state.status == ProxyRuntimeStatus.FAILED
            if (stoppedOrFailed && isTdLibProxyEnabled().getOrNull() != false) {
                _restoreFailed.value = true
            }
        } finally {
            _restoreRetrying.value = false
        }
    }

    /**
     * TDLib keeps its enabled proxy across process restarts. When that proxy is BeyGram's listener, start the listener
     * again, trying a few times because a start can fail while the app is in the background. When every try fails,
     * the proxy setting stays on and [restoreFailed] asks the user. Telegram switches to a direct connection only when
     * the user chooses that.
     */
    private suspend fun restore() {
        restoreMutex.withLock {
            // A new round starts, so a question left by an earlier round is hidden until this round fails.
            _restoreFailed.value = false
            if (listenerInUse()) return
            val enabled = awaitTdLibProxyState() ?: return
            // A start or stop may have begun while TDLib was asked; that request owns the listener now.
            if (listenerInUse()) return
            if (enabled) {
                val settled = retryUntilSuccess(MAX_RESTORE_ATTEMPTS, RESTORE_RETRY_MILLIS) { attempt ->
                    // The user may have turned the proxy off during the round. That choice wins, so the round ends.
                    if (isTdLibProxyEnabled().getOrNull() == false) {
                        MihomoRuntimeDiagnostics.event("backend", "restore stopped; proxy turned off meanwhile")
                        return@retryUntilSuccess true
                    }
                    startProxy()
                        .onSuccess { refreshConnections() }
                        .onFailure { MihomoRuntimeDiagnostics.event("backend", "restore attempt $attempt failed") }
                        .isSuccess
                }
                if (!settled) {
                    _restoreFailed.value = true
                    MihomoRuntimeDiagnostics.event("backend", "restore failed $MAX_RESTORE_ATTEMPTS times; user decides")
                }
                return
            }
            if (mihomo.profileExists()) prepareCoreWithoutListener()
        }
    }

    /** Asks TDLib whether it uses BeyGram's proxy. Null means TDLib never answered, so the restore must change nothing. */
    private suspend fun awaitTdLibProxyState(): Boolean? {
        repeat(TDLIB_STATE_ATTEMPTS) { attempt ->
            isTdLibProxyEnabled().onSuccess { return it }
            if (attempt < TDLIB_STATE_ATTEMPTS - 1) delay(TDLIB_STATE_RETRY_MILLIS)
        }
        MihomoRuntimeDiagnostics.event("backend", "Telegram proxy state unknown; restore skipped")
        return null
    }

    /** Loads the core, so the saved node list works, while the listener stays down because TDLib does not use it. */
    private suspend fun prepareCoreWithoutListener() {
        runCatching {
            mihomo.ensureInitialized()
            // Loading the core takes a while, and a start may have begun meanwhile. Then the listener belongs to that start.
            if (listenerInUse()) return@runCatching
            mihomo.stopProxyListener()
        }.onSuccess { refreshConnections() }
    }

    /** True while the listener is up or changing. A start or stop under way owns it, so a restore must leave it alone. */
    private fun listenerInUse(): Boolean = when (runtimeState.value.status) {
        ProxyRuntimeStatus.STARTING, ProxyRuntimeStatus.RUNNING, ProxyRuntimeStatus.STOPPING -> true
        ProxyRuntimeStatus.STOPPED, ProxyRuntimeStatus.FAILED -> false
    }

    fun updateAutoSelect(enabled: Boolean) {
        settingsStore.update { it.copy(autoSelectEnabled = enabled) }
    }

    fun updateSubscriptionUrl(url: String) {
        settingsStore.update { it.copy(subscriptionUrl = url.trim()) }
    }

    suspend fun startProxy(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            MihomoRuntimeDiagnostics.event("backend", "proxy start requested")
            if (!mihomo.profileExists()) throw UserMessageException(UiText.Res(R.string.err_vpn_no_profile), IllegalStateException("Сначала загрузите подписку"))
            // An earlier failure must not answer this start, so it is cleared before the intent is sent.
            MihomoProxyService.clearFailure()
            ContextCompat.startForegroundService(appContext, Intent(appContext, MihomoProxyService::class.java).setAction(MihomoProxyService.ACTION_START))
            val state = withTimeout(30_000) {
                MihomoProxyService.runtimeState.first { it.status == ProxyRuntimeStatus.RUNNING || it.status == ProxyRuntimeStatus.FAILED }
            }
            if (state.status == ProxyRuntimeStatus.FAILED) throw UserMessageException(state.message ?: UiText.Res(R.string.err_vpn_start_failed), IllegalStateException("Proxy service reported FAILED"))
            val tdlib = setTdLibProxy(true)
            if (tdlib.isFailure) {
                appContext.startService(Intent(appContext, MihomoProxyService::class.java).setAction(MihomoProxyService.ACTION_STOP))
                throw tdlib.exceptionOrNull() ?: UserMessageException(UiText.Res(R.string.err_vpn_telegram_connect_failed))
            }
            // Confirm TDLib selected this local proxy rather than treating EnableProxy's OK as connectivity.
            val route = isTdLibProxyEnabled().getOrNull()
            MihomoRuntimeDiagnostics.event(
                "tdlib", "EnableProxy accepted currentRoute=${when (route) {
                    true -> "subscription"
                    false -> "other"
                    null -> "unknown"
                }}; actual connectivity is reported separately"
            )
            checkSelectedRoute()
            Result.success(Unit)
        } catch (error: TimeoutCancellationException) {
            MihomoRuntimeDiagnostics.event("backend", "start timed out")
            // The service keeps starting in its own scope after this caller gives up; stop it instead of leaving a foreground notification.
            // startService throws when the app is in the background; that must not replace the timeout failure below.
            runCatching { appContext.startService(Intent(appContext, MihomoProxyService::class.java).setAction(MihomoProxyService.ACTION_STOP)) }
            Result.failure(UserMessageException(UiText.Res(R.string.err_vpn_start_timeout)))
        } catch (error: CancellationException) { throw error }
        catch (error: Exception) { MihomoRuntimeDiagnostics.failure("backend start", error); Result.failure(error) }
    }

    /** Probe the selected route once after enabling/changing it; do not block TDLib setup on upstream health. */
    private fun checkSelectedRoute() {
        val generation = routeProbeGeneration.incrementAndGet()
        MihomoProxyService.resetUpstream()
        scope.launch(Dispatchers.IO) {
            val result = MihomoProxyClient.probeUpstream()
            // Ignore a route that was replaced or disabled while its HTTPS check was in flight.
            if (generation != routeProbeGeneration.get()) return@launch
            MihomoProxyService.reportUpstream(result.reachable)
            MihomoRuntimeDiagnostics.outcome(
                "proxy_upstream",
                if (result.reachable) "Прокси: HTTPS-маршрут доступен" else "Прокси: HTTPS-проверка маршрута не прошла",
                if (result.reachable) com.beykus.beygram.diagnostics.report.Severity.INFO else com.beykus.beygram.diagnostics.report.Severity.WARNING,
                mapOf("result" to if (result.reachable) "reachable" else "unreachable",
                    "http_code" to (result.httpCode?.toString() ?: "none"),
                    "elapsed_ms" to result.elapsedMillis.toString(),
                    "error_type" to (result.errorType ?: "none"))
            )
        }
    }

    /** Turns the subscription proxy off: TDLib returns to the proxy it used before, then the listener stops. */
    suspend fun stopProxy(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            MihomoRuntimeDiagnostics.event("backend", "proxy stop requested")
            routeProbeGeneration.incrementAndGet()
            val tdlib = setTdLibProxy(false)
            if (tdlib.isFailure) throw tdlib.exceptionOrNull() ?: UserMessageException(UiText.Res(R.string.err_vpn_stop_failed))
            // TDLib no longer uses the proxy, so the restore question and hint are settled even if the listener stop fails below.
            _restoreFailed.value = false
            _restoreRetrying.value = false
            stopListenerNow()
            Result.success(Unit)
        } catch (error: TimeoutCancellationException) {
            MihomoRuntimeDiagnostics.event("backend", "stop timed out")
            Result.failure(UserMessageException(UiText.Res(R.string.err_vpn_stop_timeout)))
        } catch (error: CancellationException) { throw error }
        catch (error: Exception) { MihomoRuntimeDiagnostics.failure("backend stop", error); Result.failure(error) }
    }

    /**
     * Stops only the local listener and leaves TDLib's proxy alone. Used when the user picks a saved proxy:
     * TDLib no longer points at the listener, so keeping it running would only hold a foreground notification.
     */
    suspend fun stopListener(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            stopListenerNow()
            Result.success(Unit)
        } catch (error: TimeoutCancellationException) {
            MihomoRuntimeDiagnostics.event("backend", "listener stop timed out")
            Result.failure(UserMessageException(UiText.Res(R.string.err_vpn_stop_timeout)))
        } catch (error: CancellationException) { throw error }
        catch (error: Exception) { MihomoRuntimeDiagnostics.failure("backend listener stop", error); Result.failure(error) }
    }

    private suspend fun stopListenerNow() {
        routeProbeGeneration.incrementAndGet()
        if (runtimeState.value.status == ProxyRuntimeStatus.STOPPED) return
        appContext.startService(Intent(appContext, MihomoProxyService::class.java).setAction(MihomoProxyService.ACTION_STOP))
        withTimeout(10_000) { MihomoProxyService.runtimeState.first { it.status == ProxyRuntimeStatus.STOPPED } }
    }

    suspend fun fetchSubscription(url: String = settings.value.subscriptionUrl): Result<List<MihomoConnection>> =
        withContext(Dispatchers.IO) {
            if (_busy.value) return@withContext Result.failure(UserMessageException(UiText.Res(R.string.err_vpn_subscription_busy)))
            _busy.value = true
            try {
                VpnSubscriptionDiagnostics.event("fetch", "started")
                val trimmedUrl = url.trim()
                val response = subscriptionClient.fetch(trimmedUrl)
                VpnSubscriptionDiagnostics.event(
                    "fetch",
                    "downloaded bodyChars=${response.configuration.length}"
                )
                val proxyWasRunning = runtimeState.value.status == ProxyRuntimeStatus.RUNNING
                val groupName = mihomo.importSubscription(response.configuration)
                mihomo.stopProxyListener()
                if (proxyWasRunning) {
                    try {
                        mihomo.startProxyListener()
                    } catch (error: Exception) {
                        if (error is CancellationException) throw error
                        // The listener is already down and TDLib may still point at it. Roll TDLib back and stop the service
                        // even if the rollback fails, so the runtime state does not report a working proxy.
                        setTdLibProxy(false)
                        runCatching { stopListenerNow() }
                        throw error
                    }
                }
                settingsStore.update { it.copy(subscriptionUrl = trimmedUrl, connectionGroup = groupName) }
                var loaded = mihomo.listConnections(groupName)
                if (loaded.isNotEmpty() && loaded.none { it.selected }) {
                    mihomo.selectConnection(groupName, loaded.first().name)
                    loaded = mihomo.listConnections(groupName)
                }
                _connections.value = loaded
                _probes.value = emptyMap()
                VpnSubscriptionDiagnostics.event("fetch", "completed connectionCount=${loaded.size}")
                Result.success(loaded)
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                VpnSubscriptionDiagnostics.failure("fetch", error)
                Result.failure(error)
            } finally {
                _busy.value = false
            }
        }

    suspend fun refreshConnections(): Result<List<MihomoConnection>> = withContext(Dispatchers.IO) {
        try {
            var loaded = mihomo.listConnections(settings.value.connectionGroup)
            if (loaded.isNotEmpty() && loaded.none { it.selected }) {
                mihomo.selectConnection(settings.value.connectionGroup, loaded.first().name)
                loaded = mihomo.listConnections(settings.value.connectionGroup)
            }
            _connections.value = loaded
            MihomoRuntimeDiagnostics.event("connections", "refreshed count=${loaded.size}")
            Result.success(loaded)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            MihomoRuntimeDiagnostics.failure("connections refresh", error)
            Result.failure(error)
        }
    }

    /** Проверяет доступность Telegram через один сервер и возвращает свежий результат. */
    suspend fun probeConnection(name: String): Result<MihomoProbeResult> = withContext(Dispatchers.IO) {
        try {
            Result.success(mihomo.checkTelegram(name))
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Result.failure(error)
        }
    }

    suspend fun probeAllConnections(): Result<List<MihomoProbeResult>> = withContext(Dispatchers.IO) {
        try {
            MihomoProbeCoordinator.sweep {
            val current = mihomo.listConnections(settings.value.connectionGroup)
            val results = mutableListOf<MihomoProbeResult>()
            _probeProgress.value = ProbeProgress(0, current.size)
            _probes.value = emptyMap()
            current.chunked(MAX_PARALLEL_PROBES).forEach { batch ->
                val batchResults = coroutineScope {
                    batch.map { connection ->
                        async { mihomo.checkTelegram(connection.name) }
                    }.awaitAll()
                }
                results += batchResults
                _probes.value = results.associateBy { it.connectionName }
                _probeProgress.value = ProbeProgress(results.size, current.size)
            }
            Result.success(results.toList())
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Result.failure(error)
        } finally {
            _probeProgress.value = null
        }
    }

    suspend fun selectConnection(name: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            mihomo.selectConnection(settings.value.connectionGroup, name)
            if (runtimeState.value.status == ProxyRuntimeStatus.RUNNING) checkSelectedRoute()
            _connections.value = mihomo.listConnections(settings.value.connectionGroup)
            Result.success(Unit)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Result.failure(error)
        }
    }

    companion object {
        private const val MAX_PARALLEL_PROBES = 4
        private const val TDLIB_STATE_ATTEMPTS = 3
        private const val TDLIB_STATE_RETRY_MILLIS = 2_000L
        private const val MAX_RESTORE_ATTEMPTS = 5
        private const val RESTORE_RETRY_MILLIS = 2_000L

        @Volatile private var instance: VpnBackend? = null

        /** Returns the process-wide backend. The first caller's [scope] owns its background work. */
        fun getInstance(
            context: Context,
            connectionState: StateFlow<TelegramConnectionState>,
            scope: CoroutineScope,
            setTdLibProxy: suspend (Boolean) -> Result<Unit>,
            isTdLibProxyEnabled: suspend () -> Result<Boolean>
        ): VpnBackend = instance ?: synchronized(this) {
            instance ?: VpnBackend(context, connectionState, scope, setTdLibProxy, isTdLibProxyEnabled).also { instance = it }
        }
    }
}

internal data class ProbeProgress(val completed: Int, val total: Int)
