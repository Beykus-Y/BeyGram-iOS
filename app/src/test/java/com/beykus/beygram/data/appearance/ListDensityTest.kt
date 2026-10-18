package com.beykus.beygram.data.appearance

import org.junit.Assert.assertEquals
import org.junit.Test

class ListDensityTest {
    @Test fun storedNamesReadBackToTheSameDensity() {
        ListDensity.entries.forEach { density -> assertEquals(density, listDensityFromStored(density.name)) }
    }

    @Test fun missingOrUnknownStoredValueIsComfortable() {
        assertEquals(ListDensity.Comfortable, listDensityFromStored(null))
        assertEquals(ListDensity.Comfortable, listDensityFromStored("Dense"))
    }

    @Test fun defaultChoiceIsTheDensityBeyGramHasAlwaysHad() {
        assertEquals(ListDensity.Comfortable, AppearanceConfig().density)
    }
}
