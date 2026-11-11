package com.twince.alarm;

/** Owns one cancellable deadline. A generation also invalidates already queued callbacks. */
final class RingTimeout {
    interface Scheduler {
        void post(Runnable task, long delayMillis);
        void remove(Runnable task);
    }

    static final long DEFAULT_DURATION_MILLIS = 120_000L;
    private final Scheduler scheduler;
    private final long durationMillis;
    private Runnable pending;
    private long generation;

    RingTimeout(Scheduler scheduler, long durationMillis) {
        this.scheduler = scheduler;
        this.durationMillis = durationMillis;
    }

    void start(Runnable onTimeout) {
        cancel();
        final long current = generation;
        pending = () -> {
            if (current != generation || pending == null) return;
            pending = null;
            generation++;
            onTimeout.run();
        };
        scheduler.post(pending, durationMillis);
    }

    void cancel() {
        generation++;
        if (pending != null) scheduler.remove(pending);
        pending = null;
    }
}
