package com.twince.alarm

/** Process-local identity of the ringing instance; all access is on the main thread. */
internal object RingState {
    private var active: Long? = null
    private val finished = LinkedHashSet<Long>()
    private val listeners = mutableSetOf<(Long?) -> Unit>()

    fun isActive(token: Long) = active == token
    fun isFinished(token: Long) = token in finished

    fun begin(token: Long) {
        active = token
        listeners.toList().forEach { it(active) }
    }

    fun finish(token: Long) {
        finished.add(token)
        if (finished.size > 256) finished.remove(finished.first())
        if (active == token) {
            active = null
            listeners.toList().forEach { it(null) }
        }
    }

    fun addListener(listener: (Long?) -> Unit) {
        listeners.add(listener)
        listener(active)
    }

    fun removeListener(listener: (Long?) -> Unit) { listeners.remove(listener) }
}
