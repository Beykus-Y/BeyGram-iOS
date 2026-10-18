package com.beykus.beygram.ui.screens.chat

import androidx.compose.ui.unit.dp
import com.beykus.beygram.data.appearance.BubbleStyle
import com.beykus.beygram.data.appearance.ListDensity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BubbleMetricsTest {
    @Test fun defaultsAreTheLookBeyGramHasAlwaysHad() {
        assertEquals(
            BubbleMetrics(
                cornerRadius = 20.dp, tailRadius = 6.dp, sideInset = 14.dp,
                textInset = 12.dp, textTopInset = 8.dp, itemSpacing = 8.dp, listPadding = 16.dp,
                replyRadius = 12.dp, circleTopInset = 4.dp
            ),
            BubbleMetrics()
        )
    }

    @Test fun roundedComfortableIsTheDefaultLook() {
        assertEquals(BubbleMetrics(), bubbleMetricsFor(BubbleStyle.Rounded, ListDensity.Comfortable))
    }

    @Test fun everyChoiceKeepsTheTailSmallerThanTheCorners() {
        BubbleStyle.entries.forEach { style ->
            ListDensity.entries.forEach { density ->
                val metrics = bubbleMetricsFor(style, density)
                assertTrue("$style, $density", metrics.tailRadius < metrics.cornerRadius)
            }
        }
    }

    @Test fun styleChangesTheCornersAndDensityChangesTheRhythm() {
        val soft = bubbleMetricsFor(BubbleStyle.Soft, ListDensity.Comfortable)
        assertTrue(soft.cornerRadius < BubbleMetrics().cornerRadius)
        assertEquals(BubbleMetrics().itemSpacing, soft.itemSpacing)

        val compact = bubbleMetricsFor(BubbleStyle.Rounded, ListDensity.Compact)
        val spacious = bubbleMetricsFor(BubbleStyle.Rounded, ListDensity.Spacious)
        assertEquals(BubbleMetrics().cornerRadius, compact.cornerRadius)
        assertTrue(compact.itemSpacing < BubbleMetrics().itemSpacing)
        assertTrue(BubbleMetrics().itemSpacing < spacious.itemSpacing)
        assertTrue(compact.listPadding < spacious.listPadding)
    }
}
