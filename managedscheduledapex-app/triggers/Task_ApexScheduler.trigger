/**
 * This is a trigger for tasks needed for the daily sescheduler.
 * 
 * @author Bill Riemers <briemers@redhat.com
 * @since 2020-11-15 Created
 */
trigger Task_ApexScheduler on Task (after insert, after update, after delete) {
    ApexSchedulerTaskCallableTrigger.triggerManagement(null);
}