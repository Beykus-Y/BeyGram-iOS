package com.beykus.beygram.data.appearance

import org.junit.Assert.assertEquals
import org.junit.Test

class BubbleStyleTest {
    @Test fun storedNamesReadBackToTheSameStyle() {
        BubbleStyle.entries.forEach { style -> assertEquals(style, bubbleStyleFromStored(style.name)) }
    }

    @Test fun missingOrUnknownStoredValueIsRounded() {
        assertEquals(BubbleStyle.Rounded, bubbleStyleFromStored(null))
        assertEquals(BubbleStyle.Rounded, bubbleStyleFromStored("Round"))
    }

    @Test fun defaultChoiceIsTheRoundedBubblesBeyGramHasAlwaysHad() {
        assertEquals(BubbleStyle.Rounded, AppearanceConfig().bubbleStyle)
    }
}
