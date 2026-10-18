package com.beykus.beygram.data.vpn

import com.beykus.beygram.R
import com.beykus.beygram.domain.UiText
import com.beykus.beygram.domain.UserMessageException
import com.beykus.beygram.domain.model.TelegramConnectionState
import com.beykus.beygram.domain.model.VpnNetworkState
import com.beykus.beygram.domain.model.VpnSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Waits for a sustained TDLib Connecting state before probing. Network changes cancel
 * in-flight checks, and a small concurrency limit prevents a large subscription from
 * creating a burst of sockets.
 */
internal class TelegramAutoSelector(
    private val scope: CoroutineScope,
    private val connectionState: Flow<TelegramConnectionState>,
    private val networkState: Flow<VpnNetworkState>,
    private val settings: Flow<VpnSettings>,
    private val runtimeState: Flow<ProxyRuntimeState>,
    private val mihomo: MihomoCoreBridge,
    private val report: (AutoSelectEvent) -> Unit = {}
) {
    private var job: Job? = null
    private val checking = AtomicBoolean(false)

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch(Dispatchers.IO) {
            combine(connectionState, networkState, settings, runtimeState) { connection, network, currentSettings, runtime ->
                AutoSelectInputs(connection, network, currentSettings, runtime)
            }.collectLatest { inputs ->
                val settings = inputs.settings
                if (!settings.autoSelectEnabled || !inputs.network.canReachInternetForTelegram() ||
                    inputs.connection != TelegramConnectionState.Connecting || inputs.runtime.status != ProxyRuntimeStatus.RUNNING
                ) return@collectLatest

                delay(settings.handoverDelayMillis)
                while (inputs.settings.autoSelectEnabled &&
                    inputs.connection == TelegramConnectionState.Connecting &&
                    inputs.runtime.status == ProxyRuntimeStatus.RUNNING &&
                    inputs.network.canReachInternetForTelegram()
                ) {
                    if (checking.compareAndSet(false, true)) {
                        try {
                            MihomoProbeCoordinator.sweep { evaluateAndSelect(settings.connectionGroup) }
                        } finally {
                            checking.set(false)
                        }
                    }
                    delay(RETRY_INTERVAL_MS)
                }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private suspend fun evaluateAndSelect(groupName: String) {
        val connections = try {
            mihomo.listConnections(groupName)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(AutoSelectEvent.Failed((error as? UserMessageException)?.text ?: UiText.Res(R.string.err_vpn_servers_load_failed)))
            return
        }
        if (connections.isEmpty()) {
            report(AutoSelectEvent.NoConnections)
            return
        }

        val results = mutableListOf<com.beykus.beygram.domain.model.MihomoProbeResult>()
        connections.chunked(MAX_PARALLEL_PROBES).forEach { batch ->
            val batchResults = coroutineScope {
                batch.map { connection ->
                    async(Dispatchers.IO) { mihomo.checkTelegram(connection.name) }
                }.awaitAll()
            }
            results += batchResults
            batchResults.forEach { report(AutoSelectEvent.Probed(it)) }
        }

        val fastest = results.asSequence()
            .filter { it.telegramReachable && it.delayMillis != null }
            .minByOrNull { it.delayMillis!! }
        if (fastest == null) {
            report(AutoSelectEvent.NoReachableConnection)
            return
        }
        val selected = connections.firstOrNull { it.name == fastest.connectionName }
        if (selected?.selected == true) {
            report(AutoSelectEvent.Kept(fastest.connectionName, fastest.delayMillis!!))
            return
        }
        try {
            mihomo.selectConnection(groupName, fastest.connectionName)
            report(AutoSelectEvent.Switched(fastest.connectionName, fastest.delayMillis!!))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(AutoSelectEvent.Failed((error as? UserMessageException)?.text ?: UiText.Res(R.string.err_vpn_server_select_failed)))
        }
    }

    private data class AutoSelectInputs(
        val connection: TelegramConnectionState,
        val network: VpnNetworkState,
        val settings: VpnSettings,
        val runtime: ProxyRuntimeState
    )

    private fun VpnNetworkState.canReachInternetForTelegram(): Boolean =
        internetAvailable && (wifiAvailable || cellularAvailable)

    companion object {
        private const val MAX_PARALLEL_PROBES = 4
        private const val RETRY_INTERVAL_MS = 20_000L
    }
}

sealed interface AutoSelectEvent {
    data class Probed(val result: com.beykus.beygram.domain.model.MihomoProbeResult) : AutoSelectEvent
    data class Switched(val connectionName: String, val delayMillis: Long) : AutoSelectEvent
    data class Kept(val connectionName: String, val delayMillis: Long) : AutoSelectEvent
    data class Failed(val message: UiText) : AutoSelectEvent
    data object NoConnections : AutoSelectEvent
    data object NoReachableConnection : AutoSelectEvent
}
