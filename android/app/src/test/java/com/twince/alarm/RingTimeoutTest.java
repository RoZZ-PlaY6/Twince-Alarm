package com.twince.alarm;

/** Run with javac/java; no Android runtime or real waiting is required. */
public final class RingTimeoutTest {
    static final class FakeScheduler implements RingTimeout.Scheduler {
        Runnable task;
        long due;
        long now;
        public void post(Runnable task, long delay) { this.task = task; due = now + delay; }
        public void remove(Runnable task) { if (this.task == task) this.task = null; }
        void advance(long millis) {
            now += millis;
            if (task != null && now >= due) { Runnable t = task; task = null; t.run(); }
        }
    }
    static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        FakeScheduler clock = new FakeScheduler();
        RingTimeout timer = new RingTimeout(clock, RingTimeout.DEFAULT_DURATION_MILLIS);
        boolean[] audioVibrationUiPreview = {true, true, true, true};
        boolean[] futureScheduled = {true};
        int[] completions = {0};
        Runnable dismiss = () -> {
            completions[0]++;
            for (int i = 0; i < audioVibrationUiPreview.length; i++) audioVibrationUiPreview[i] = false;
        };
        timer.start(dismiss);
        Runnable stale = clock.task;
        clock.advance(119_999);
        check(completions[0] == 0);
        clock.advance(1);
        check(completions[0] == 1);
        for (boolean active : audioVibrationUiPreview) check(!active);
        check(futureScheduled[0]);
        stale.run();
        check(completions[0] == 1);
        timer.start(dismiss);
        stale = clock.task;
        timer.cancel();
        clock.advance(120_000);
        stale.run();
        check(completions[0] == 1);
        timer.start(dismiss);
        stale = clock.task;
        timer.start(dismiss);
        stale.run();
        check(completions[0] == 1);
        clock.advance(120_000);
        check(completions[0] == 2);
        check(futureScheduled[0]);
        System.out.println("RingTimeout tests passed");
    }
}
