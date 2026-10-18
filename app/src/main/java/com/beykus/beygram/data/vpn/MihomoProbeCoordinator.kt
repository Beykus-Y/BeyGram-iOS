package com.beykus.beygram.data.vpn

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * One process-wide Mihomo testDelay sweep at a time. Manual checks and auto-select share
 * this gate so they cannot saturate the native core or race an in-flight selection.
 * Waiting is cancellable: collectLatest can abandon an obsolete auto-select sweep.
 */
internal object MihomoProbeCoordinator {
    private val gate = Mutex()

    suspend fun <T> sweep(block: suspend () -> T): T = gate.withLock { block() }
}
