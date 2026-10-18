package com.beykus.beygram.data.vpn

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Test

class MihomoProbeCoordinatorTest {
    @Test
    fun manualAndAutoSweepsNeverOverlap() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var concurrent = 0
        var maxConcurrent = 0
        val first = launch {
            MihomoProbeCoordinator.sweep {
                concurrent++
                maxConcurrent = maxOf(maxConcurrent, concurrent)
                entered.complete(Unit)
                try { release.await() } finally { concurrent-- }
            }
        }
        entered.await()
        val second = launch {
            MihomoProbeCoordinator.sweep {
                concurrent++
                maxConcurrent = maxOf(maxConcurrent, concurrent)
                concurrent--
            }
        }
        try {
            yield()
            assertEquals(1, maxConcurrent)
        } finally {
            release.complete(Unit)
        }
        first.join()
        second.join()
        assertEquals(1, maxConcurrent)
        assertEquals(0, concurrent)
    }

    @Test
    fun canceledWaiterDoesNotRunAfterCurrentSweep() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val first = launch {
            MihomoProbeCoordinator.sweep {
                entered.complete(Unit)
                release.await()
            }
        }
        entered.await()
        var ran = false
        val canceled = launch { MihomoProbeCoordinator.sweep { ran = true } }
        canceled.cancelAndJoin()
        release.complete(Unit)
        first.join()
        assertEquals(false, ran)
    }
}
