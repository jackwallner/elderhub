package com.jackwallner.aging

import android.app.Application
import android.content.Context
import com.jackwallner.aging.data.CareStore
import com.jackwallner.aging.data.FilePersistence
import com.jackwallner.aging.data.KeyValueStore
import com.jackwallner.aging.data.SharedPreferencesStore
import com.jackwallner.aging.data.StoreService
import java.io.File

/** Every shared object, built once per process. */
class AppGraph(context: Context) {
    val defaults: KeyValueStore = SharedPreferencesStore(context)
    val care = CareStore(FilePersistence(File(context.filesDir, "care.json")))
    val store = StoreService(context.applicationContext, defaults)
}

class AgingApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}
