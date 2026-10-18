package com.beykus.beygram.data.appearance

/**
 * How much room the message list and the chat list give each item. [Comfortable] is the look BeyGram has always had.
 * Choices are stored by name, so a missing or unknown stored value means [Comfortable].
 */
enum class ListDensity { Compact, Comfortable, Spacious }

/** Reads a stored [ListDensity] name. Missing or unknown values fall back to [ListDensity.Comfortable]. */
internal fun listDensityFromStored(stored: String?): ListDensity =
    ListDensity.entries.firstOrNull { it.name == stored } ?: ListDensity.Comfortable
