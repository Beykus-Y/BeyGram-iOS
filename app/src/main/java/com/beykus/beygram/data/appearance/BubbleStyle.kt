package com.beykus.beygram.data.appearance

/**
 * The shape of the message bubbles. [Rounded] is the look BeyGram has always had.
 * Choices are stored by name, so a missing or unknown stored value means [Rounded].
 */
enum class BubbleStyle { Rounded, Soft, Square }

/** Reads a stored [BubbleStyle] name. Missing or unknown values fall back to [BubbleStyle.Rounded]. */
internal fun bubbleStyleFromStored(stored: String?): BubbleStyle =
    BubbleStyle.entries.firstOrNull { it.name == stored } ?: BubbleStyle.Rounded
