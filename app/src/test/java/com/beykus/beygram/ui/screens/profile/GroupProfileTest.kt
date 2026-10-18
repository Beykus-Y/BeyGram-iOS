package com.beykus.beygram.ui.screens.profile

import org.junit.Assert.assertEquals
import org.junit.Test

class GroupProfileTest {
    @Test fun headerIsExpandedWhileItIsAtTheTop() {
        assertEquals(0f, collapseFraction(firstVisibleIndex = 0, scrollOffsetPx = 0, collapseRangePx = 200), 0f)
    }

    @Test fun collapseFollowsScrollUntilTheHeaderIsGone() {
        assertEquals(0.5f, collapseFraction(firstVisibleIndex = 0, scrollOffsetPx = 100, collapseRangePx = 200), 0.0001f)
        assertEquals(1f, collapseFraction(firstVisibleIndex = 0, scrollOffsetPx = 300, collapseRangePx = 200), 0f)
    }

    @Test fun headerStaysCollapsedOnceTheNextItemIsFirst() {
        assertEquals(1f, collapseFraction(firstVisibleIndex = 1, scrollOffsetPx = 0, collapseRangePx = 200), 0f)
    }

    @Test fun unmeasuredHeaderDoesNotCollapse() {
        assertEquals(0f, collapseFraction(firstVisibleIndex = 0, scrollOffsetPx = 50, collapseRangePx = 0), 0f)
    }
}
