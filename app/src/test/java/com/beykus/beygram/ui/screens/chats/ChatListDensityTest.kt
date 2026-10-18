package com.beykus.beygram.ui.screens.chats

import androidx.compose.ui.unit.dp
import com.beykus.beygram.data.appearance.ListDensity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatListDensityTest {
    @Test fun defaultIsTheRowPaddingBeyGramHasAlwaysHad() {
        assertEquals(10.dp, ChatListDensity().rowVerticalPadding)
    }

    @Test fun densityMapsToTheRowPaddingOfEachStep() {
        assertEquals(ChatListDensity(), chatListDensityFor(ListDensity.Comfortable))
        assertTrue(chatListDensityFor(ListDensity.Compact).rowVerticalPadding < ChatListDensity().rowVerticalPadding)
        assertTrue(ChatListDensity().rowVerticalPadding < chatListDensityFor(ListDensity.Spacious).rowVerticalPadding)
    }
}
