package com.beykus.beygram.data.vpn

import android.content.Context
import com.beykus.beygram.BuildConfig
import com.beykus.beygram.R
import com.beykus.beygram.domain.UiText
import com.beykus.beygram.domain.model.VpnSettings
import java.net.Authenticator
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.PasswordAuthentication
import java.net.Proxy
import java.net.Socket
import java.net.URL

/** Result of the selected path, not an individual node's testDelay result. */
internal data class UpstreamProbeResult(
    val reachable: Boolean,
    val httpCode: Int?,
    val elapsedMillis: Long,
    val errorType: String? = null
)

/** Shared loopback SOCKS entry point for BeyGram-owned Java network clients. */
internal object MihomoProxyClient {
    const val HOST = "127.0.0.1"
    /** Differs per variant: Dev and Stable on one device would otherwise compete for the same loopback port. */
    val PORT: Int = BuildConfig.MIHOMO_PROXY_PORT

    private val socksProxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress(HOST, PORT))

    @Volatile private var credentials: LoopbackProxyCredentials? = null

    /** Gives Java clients the loopback SOCKS credentials. The authenticator answers only for this listener. */
    fun install(context: Context) {
        val loaded = LoopbackProxyCredentials.get(context)
        credentials = loaded
        Authenticator.setDefault(object : Authenticator() {
            override fun getPasswordAuthentication(): PasswordAuthentication? {
                val isLocalListener = requestingPort == PORT && (requestingHost == HOST || requestingHost == "localhost")
                return if (isLocalListener) PasswordAuthentication(loaded.username, loaded.password.toCharArray()) else null
            }
        })
    }

    fun isRunning(): Boolean = MihomoProxyService.runtimeState.value.status == ProxyRuntimeStatus.RUNNING

    fun routeName(): String = if (isRunning()) "local_proxy" else "direct"

    fun currentProxy(): Proxy? = socksProxy.takeIf { isRunning() }

    /** Goes through the listener while it runs. Pass null to connect directly. */
    fun openConnection(url: URL, proxy: Proxy? = currentProxy()): HttpURLConnection {
        return (if (proxy == null) url.openConnection() else url.openConnection(proxy)) as HttpURLConnection
    }

    fun newSocket(): Socket = Socket(socksProxy)

    /**
     * End-to-end HTTPS check through the very same authenticated SOCKS listener TDLib uses.
     * Unlike Mihomo testDelay (which tests an individual node), this verifies the currently
     * selected upstream route: SOCKS5 authentication, CONNECT, TLS and a short HTTP request.
     * A non-2xx HTTP response still proves the network path is working.
     */
    fun probeUpstream(): UpstreamProbeResult {
        val started = System.nanoTime()
        return try {
            val connection = openConnection(URL(VpnSettings.TELEGRAM_HEALTH_CHECK_URL), socksProxy)
            try {
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.requestMethod = "HEAD"
                connection.instanceFollowRedirects = false
                val code = connection.responseCode
                UpstreamProbeResult(code in 100..599, code.takeIf { it in 100..599 },
                    (System.nanoTime() - started) / 1_000_000L)
            } finally {
                connection.disconnect()
            }
        } catch (error: Exception) {
            // Never include URL, credentials or response bodies in the shareable report.
            UpstreamProbeResult(false, null, (System.nanoTime() - started) / 1_000_000L,
                error.javaClass.simpleName)
        }
    }

    /**
     * Waits until BeyGram's own listener answers with this installation's credentials. An open port is not enough:
     * when another app already holds it, Mihomo's bind fails silently and TDLib would wait on that app's proxy.
     */
    fun awaitReady(credentials: LoopbackProxyCredentials, timeoutMillis: Long = 5_000) {
        val deadline = System.nanoTime() + timeoutMillis * 1_000_000
        var lastError: Exception? = null
        while (System.nanoTime() < deadline) {
            val result = try {
                LoopbackSocksProbe.check(HOST, PORT, credentials.username, credentials.password, 300, 1_000)
            } catch (error: Exception) {
                lastError = error
                Thread.sleep(100)
                continue
            }
            if (result == LoopbackSocksProbe.Result.OWN_LISTENER) return
            MihomoRuntimeDiagnostics.event("listener", "port $PORT is held by another app; credentials rejected")
            throw coreUserError(UiText.Res(R.string.err_vpn_listener_port_taken), "Порт прокси занят другим приложением")
        }
        MihomoRuntimeDiagnostics.event("listener", "port not ready error=${lastError?.javaClass?.simpleName ?: "none"}")
        throw coreUserError(UiText.Res(R.string.err_vpn_listener_not_accepting), "Прокси не принимает подключения")
    }
}
