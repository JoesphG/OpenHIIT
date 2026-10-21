package com.codepup.openhiit_wear

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/**
 * Receives every run snapshot from the phone, even while the app is closed,
 * and keeps the run's alerts and icon in step with it.
 */
class RunListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        val changed = events.filter {
            it.type == DataEvent.TYPE_CHANGED &&
                it.dataItem.uri.path == WearProtocol.RUN_PATH
        }
        if (changed.isEmpty()) {
            return
        }
        RunAlerts.sync(this, WearProtocol.json(changed.last().dataItem))
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path == WearProtocol.PONG_PATH) {
            ClockSync.onPong(this, event.data)
        }
    }
}
