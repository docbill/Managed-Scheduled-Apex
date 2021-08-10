// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is a callable trigger class for tasks. 
 * 
 * @version 2020-12-09
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2020-11-19 - created
 * @since 2020-12-09 - Renamed from DailyScheduler_TaskTrigger
 */
public class ApexSchedulerTaskCallableTrigger implements Callable {
    @TestVisible
    static Boolean deactivateAll = false;
    // getInstance will create the setting if needed, so there is no danger of a null exception.
    @TestVisible
    static String TRIGGER_MANAGEMENT_CLASSNAME = Scheduled_Apex_Settings__c.getInstance().TriggerManagementClass__c;

    public ApexSchedulerTaskCallableTrigger() {}

    // If you use this variable instead of Trigger, for referencing values passed into the trigger.
    @TestVisible 
    TriggerArguments localTrigger;

    Map<Id,Task> newMap;
    Map<Id,Task> oldMap;

    /**
     * This is a trigger to manage the monitored activities objects for Tasks.   This is 
     * a depreciated way to inject the classes needed in the daily scheduler.
     */
    public Boolean monitoredActivities() {
        if( localTrigger.isAfter && ! localTrigger.isUndelete ) {
            List<Task> taskList = new List<Task>();
            List<MonitoredActivity__c> monitoredActivityList = new List<MonitoredActivity__c>();
            if(! localTrigger.isDelete ) {
                Set<String> subjects = new Set<String>();
                for(Task t : newMap.values()) {
                    if(t.Monitor__c == true) {
                        Task oldTask = null;
                        if(oldMap != null) {
                            oldTask = oldMap.get(t.Id);
                        }
                        if( oldTask == null 
                            || t.ActivityDate != oldTask.ActivityDate
                            || t.OwnerId != oldTask.OwnerId
                            || t.RecordTypeId != oldTask.RecordTypeId
                            || t.Status != oldTask.Status
                            || t.Subject != oldTask.Subject )
                        {
                            subjects.add(t.Subject);
                            if(oldTask != null) {
                                subjects.add(oldTask.Subject);
                            }
                            // add a monitored activity and tasks to the lists
                            monitoredActivityList.add(new MonitoredActivity__c(
                                ActivityDate__c = DateTime.newInstance(t.ActivityDate,Time.newInstance(0,0,0,0)),
                                OwnerId = t.OwnerId,
                                RecordTypeId__c = t.RecordTypeId,
                                Status__c = t.Status,
                                Subject__c = t.Subject,
                                TaskId__c = t.Id,
                                SkippedCount__c = 0.0));
                            taskList.add(t);
                        }
                    }
                }
                if(! monitoredActivityList.isEmpty()) {
                    // We do not allow more than one monitored activity per subject
                    Database.delete([
                        select Id
                        from MonitoredActivity__c
                        where Subject__c in :subjects
                            and TaskId__c not in :newMap.keySet() ],false);
                    // insert new records and update existing ones
                    for(Database.UpsertResult sr : Database.upsert(monitoredActivityList,MonitoredActivity__c.Fields.TaskId__c,false)) {
                        Task t = taskList.remove(0);
                        MonitoredActivity__c ma = monitoredActivityList.remove(0);
                        if(! sr.isSuccess()) {
                            // return an error
                            t.addError('Failed to create or update Monitored Activity: '+sr.getErrors());
                            localTrigger.callableArguments.put('hasErrors',true);
                        }
                    }
                }
            }
            if(! localTrigger.isInsert) {
                Set<Id> taskIds = new Set<Id>();
                if (localTrigger.isDelete) {
                    for(Task t : oldMap.values()) {
                        if(t.Monitor__c == true) {
                            taskIds.add(t.Id);
                        }
                    }
                }
                else {
                    for(Task t : newMap.values()) {
                        if(t.Monitor__c != true && oldMap.get(t.Id).Monitor__c == true) {
                            taskIds.add(t.Id);
                        }
                    }
                }
                if(! taskIds.isEmpty()) {
                    // for now we are ignoring delete errors, leaving orphaned records
                    List<MonitoredActivity__c> monitoredActivities = [
                        select TaskId__c
                        from MonitoredActivity__c
                        where TaskId__c in :taskIds];
                    for(Database.DeleteResult dr : Database.delete(monitoredActivities,false)) {
                        MonitoredActivity__c ma = monitoredActivities.remove(0);
                        if(! dr.isSuccess()) {
                            Task t = oldMap.get(ma.TaskId__c);
                            if(localTrigger.isUpdate) {
                                t = newMap.get(ma.TaskId__c);
                            }
                            t.addError('Failed to delete monitored activity: '+dr.getErrors());
                            localTrigger.callableArguments.put('hasErrors',true);
                        }
                    }
                }
            }
        }
        return null;
    }

    /**
     * Called to execute trigger methods.
     */
    public Object call(String action, Map<String, Object> args) {
        this.localTrigger = new TriggerArguments(args);
        //this.newList = (List<Task>)localTrigger.callableArguments.get('new');
        this.newMap = (Map<Id,Task>)localTrigger.callableArguments.get('newMap');
        //this.oldList = (List<Task>)localTrigger.callableArguments.get('old');
        this.oldMap = (Map<Id,Task>)localTrigger.callableArguments.get('oldMap');
        if(! deactivateAll) {
            switch on action {
                when 'Task_After.monitoredActvitiesCallable','ApexSchedulerTaskCallableTrigger' {
                    monitoredActivities();
                }
                when else {
                    throw new ExtensionMalformedCallException('Method not implemented: '+action);
                }
            }
        }
        // we actually ignore the return value, but lets return something anyway
        return null;
    }


    public class ExtensionMalformedCallException extends Exception {}

    // The following method and classes are included so we our package for the scheduler does not
    // need to depend on a TriggerManagement or TriggerArguments class existing in the org.

    /**
     * Because this is a non-dependent package we need to use reflection
     * to create the TriggerManagement class, and just call this directly
     * when that fails.
     * 
     * @param args normally null except in a test class
     */
    public static Callable triggerManagement(Map<String,Object> args) {
        Callable c;
        try {
            c = (Callable)Type.forName(TRIGGER_MANAGEMENT_CLASSNAME).newInstance();
        }
        catch(Exception ex) {
            c = new ApexSchedulerTaskCallableTrigger();
        }
        c.call(ApexSchedulerTaskCallableTrigger.class.getName(),args);
        return c;
    }

    // Because this is a non-dependent package we need to define a local version of TriggerArguments, rather than
    // relying on the class already existing in our sandbox.  This is a simplified version of that class because
    // we only need to define the fields and feature we are using.
    @TestVisible
    class TriggerArguments {
        public Boolean isAfter { get { return (true == (Boolean)callableArguments.get('isAfter')); } }
        public Boolean isInsert { get { return (true == (Boolean)callableArguments.get('isInsert')); } }
        public Boolean isUpdate { get { return (true == (Boolean)callableArguments.get('isUpdate')); } }
        public Boolean isDelete { get { return (true == (Boolean)callableArguments.get('isDelete')); } }
        public Boolean isUndelete { get { return (true == (Boolean)callableArguments.get('isUndelete')); } }

        public Map<String,Object> callableArguments {
            get;
            set {
                if(value == null) {
                    value = new Map<String,Object>();
                }
                callableArguments = value;
            }
        }

        TriggerArguments(Map<String,Object> args) {
            this.callableArguments = args;
            if(this.callableArguments.isEmpty()) {
                this.callableArguments.putAll(new Map<String,Object>{
                    'new' => Trigger.new,
                    'newMap' => Trigger.newMap,
                    'old' => Trigger.old,
                    'oldMap' => Trigger.oldMap,
                    'isAfter' => true == Trigger.isAfter,
                    'isBefore' => true == Trigger.isBefore,
                    'isInsert' => true == Trigger.isInsert,
                    'isUpdate' => true == Trigger.isUpdate,
                    'isDelete' => true == Trigger.isDelete,
                    'isUndelete' => true == Trigger.isUndelete
                });
            }
        }
    }
}