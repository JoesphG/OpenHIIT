package com.codepup.openhiit_wear

import android.net.Uri
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem

/** Paths and keys shared with the phone app's MainActivity. */
object WearProtocol {
    const val CHANNEL = "openhiit/wear"

    /** Data item the phone writes with the current run snapshot. */
    const val RUN_PATH = "/openhiit/run"

    /** Message path for commands sent from the watch to the phone. */
    const val COMMAND_PATH = "/openhiit/command"

    const val KEY_JSON = "json"
    const val KEY_TS = "ts"

    val runUri: Uri = Uri.Builder().scheme("wear").path(RUN_PATH).build()

    fun json(item: DataItem): String? =
        DataMapItem.fromDataItem(item).dataMap.getString(KEY_JSON)

    fun timestamp(item: DataItem): Long =
        DataMapItem.fromDataItem(item).dataMap.getLong(KEY_TS)
}
