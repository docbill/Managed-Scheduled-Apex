// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * Test class for ApexSchedulerTaskCallableTrigger
 * @version 2020-12-09
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2020-11-19 - created
 * @since 2020-12-09 - Renamed from DailyScheduler_TaskTrigger
 */
@isTest
public class ApexSchedulerTaskCallableTriggerTest {
    static final String MONITORED_ACTIVITIES_SETTING = 'Task_After.monitoredActvitiesCallable';

    static List<Task> taskList {
        get {
            if(taskList == null) {
                taskList = ( new List<Task>{
                    new Task(
                        ActivityDate=System.today().addDays(1),
                        IsReminderSet = true,
                        ReminderDateTime = DateTime.now().addDays(1),
                        OwnerId=UserInfo.getUserId(),
                        RecordTypeId = ApexScheduler.SCHEDULED_TASK_RECORDTYPE_ID,
                        Subject='Trigger Test' )
                } );
            }
            return taskList;
        }
        set;
    }

    @isTest
    static void monitorActivitiesTest() {
        // turn off the triggers we are testing
        ApexSchedulerTaskCallableTrigger.deactivateAll = true;
        insert taskList;
        for(Task tk : taskList) {
            tk.Monitor__c = true;
        }
        // Turn on the triggers we are testing, and make sure everything is tested.
        ApexSchedulerTaskCallableTrigger.deactivateAll = false;

        // insert test
        Callable afterTrigger = new ApexSchedulerTaskCallableTrigger();
        Map<Id,Task> newMap = new Map<Id,Task>(taskList.deepclone(true,true,true));
        Map<String,Object> insertArgs = (new Map<String,Object>{
            'newMap' => newMap,
            'isAfter' => true,
            'isInsert' => true
        });
        afterTrigger.call(MONITORED_ACTIVITIES_SETTING, insertArgs);
        List<MonitoredActivity__c> maList = [
            select Subject__c,TaskId__c from MonitoredActivity__c 
            where TaskId__c in :newMap.keySet() ];
        for(MonitoredActivity__c ma : maList )
        {
            Task tk = newMap.remove(ma.TaskId__c);
            System.assertNotEquals(null,tk,'task from MonitoredActivity');
            System.assertEquals(tk.Subject,ma.Subject__c,'subject check');
        }
        System.assertEquals(0,newMap.size(),'failed to find all tasks in MonitoredActivity__c');

        // update test
        List<Task> taskList2 = taskList.deepClone(true,true,true);
        newMap = new Map<Id,Task>(taskList2);
        for(Task tk : taskList2) {
            tk.Monitor__c = false;
        }
        Map<Id,Task> oldMap = new Map<Id,Task>(taskList.deepclone(true,true,true));
        Map<String,Object> updateArgs = (new Map<String,Object>{
            'oldMap' => oldMap,
            'newMap' => newMap,
            'isAfter' => true,
            'isUpdate' => true
        });
        afterTrigger.call(MONITORED_ACTIVITIES_SETTING, updateArgs);
        maList = [
            select Subject__c,TaskId__c,IsDeleted from MonitoredActivity__c 
            where TaskId__c in :newMap.keySet()
            ALL ROWS ];
        for(MonitoredActivity__c ma : maList )
        {
            Task tk = newMap.remove(ma.TaskId__c);
            System.assertNotEquals(null,tk,'task from MonitoredActivity');
            System.assertEquals(tk.Subject,ma.Subject__c,'subject check');
            System.assertEquals(true,ma.IsDeleted,'MonitoredActivity__c not deleted');
        }
        System.assertEquals(0,newMap.size(),'failed to find all tasks in MonitoredActivity__c');
        undelete maList;

        // delete test
        oldMap = new Map<Id,Task>(taskList.deepclone(true,true,true));
        Map<String,Object> deleteArgs = (new Map<String,Object>{
            'oldMap' => oldMap,
            'isAfter' => true,
            'isDelete' => true
        });
        afterTrigger.call(MONITORED_ACTIVITIES_SETTING, deleteArgs);
        maList = [
            select Subject__c,TaskId__c,IsDeleted from MonitoredActivity__c 
            where TaskId__c in :oldMap.keySet()
            ALL ROWS ];
        for(MonitoredActivity__c ma : maList )
        {
            Task tk = oldMap.remove(ma.TaskId__c);
            System.assertNotEquals(null,tk,'task from MonitoredActivity');
            System.assertEquals(tk.Subject,ma.Subject__c,'subject check');
            System.assertEquals(true,ma.IsDeleted,'MonitoredActivity__c not deleted');
        }
        System.assertEquals(0,oldMap.size(),'failed to find all tasks in MonitoredActivity__c');
    }
    
    @isTest
    static void triggerManagementTest() {
        // this call is just to verify we do not throw an exception
        Map<String,Object> args  = (
            new Map<String,Object>{
                'newList' => taskList.deepClone(),
                'isBefore' => true
            } );
        Callable callableTrigger = ApexSchedulerTaskCallableTrigger.triggerManagement( args );

        // for the rest of the calls, we change or settings to make sure
        // we do not actually process any trigger methods
        ApexSchedulerTaskCallableTrigger.deactivateAll = true;
        ApexSchedulerTaskCallableTrigger.TRIGGER_MANAGEMENT_CLASSNAME = null;

        callableTrigger = ApexSchedulerTaskCallableTrigger.triggerManagement(null); 
        ApexSchedulerTaskCallableTrigger.TriggerArguments localTrigger = ((ApexSchedulerTaskCallableTrigger)callableTrigger).localTrigger;
        args = localTrigger.callableArguments;        
        System.assertEquals(null,localTrigger.callableArguments.get('oldMap'),'oldMap from a null map: '+localTrigger.callableArguments);
        System.assertEquals(null,localTrigger.callableArguments.get('newMap'),'newMap from a null map: '+localTrigger.callableArguments);
        System.assertEquals(false,localTrigger.isAfter,'isAfter from a null map');
        System.assertEquals(false,localTrigger.isInsert,'isInsert from a null map');
        System.assertEquals(false,localTrigger.isUpdate,'isUpdate from a null map');
        System.assertEquals(false,localTrigger.isDelete,'isDelete from a null map');
        System.assertEquals(false,localTrigger.isUndelete,'isUndelete from a null map');

        args = new Map<String,Object>();
        callableTrigger = ApexSchedulerTaskCallableTrigger.triggerManagement(args);
        localTrigger = ((ApexSchedulerTaskCallableTrigger)callableTrigger).localTrigger;
        System.assertEquals(args,localTrigger.callableArguments,'localTrigger.callableArguments');
        System.assertEquals(null,args.get('oldMap'),'oldMap from an empty map: '+args);
        System.assertEquals(null,args.get('newMap'),'newMap from an empty map: '+args);
        System.assertEquals(false,localTrigger.isAfter,'isAfter from an empty map: '+args);
        System.assertEquals(false,localTrigger.isInsert,'isInsert from an empty map: '+args);
        System.assertEquals(false,localTrigger.isUpdate,'isUpdate from an empty map: '+args);
        System.assertEquals(false,localTrigger.isDelete,'isDelete from an empty map: '+args);
        System.assertEquals(false,localTrigger.isUndelete,'isUndelete from an empty map: '+args);

        args = new Map<String,Object>{
            'newMap' => new Map<Id,Task>(),
            'isAfter' => true,
            'isInsert' => true };
        callableTrigger = ApexSchedulerTaskCallableTrigger.triggerManagement(args);
        localTrigger = ((ApexSchedulerTaskCallableTrigger)callableTrigger).localTrigger;
        System.assertEquals(args,localTrigger.callableArguments,'localTrigger.callableArguments');
        System.assertEquals(null,args.get('oldMap'),'oldMap from a non-empty map: '+args);
        System.assertNotEquals(null,args.get('newMap'),'newMap from a non-empty map: '+args);
        System.assertEquals(true,localTrigger.isAfter,'isAfter from an non-empty map: '+args);
        System.assertEquals(true,localTrigger.isInsert,'isInsert from an non-empty map: '+args);
        System.assertEquals(false,localTrigger.isUpdate,'isUpdate from an non-empty map: '+args);
        System.assertEquals(false,localTrigger.isDelete,'isDelete from an non-empty map: '+args);
        System.assertEquals(false,localTrigger.isUndelete,'isUndelete from a non-empty map: '+args);
    }
    
    @IsTest
    static void exceptionTest() {
        try {
            new ApexSchedulerTaskCallableTrigger().call('anything',new Map<String,Object>());
            System.assert(true,'This action is not defined.  We should never reach this line');
        }
        catch(ApexSchedulerTaskCallableTrigger.ExtensionMalformedCallException ex) {
            System.debug('expected exception: '+ex);
        }
        try {
            new ApexSchedulerTaskCallableTrigger().call(MONITORED_ACTIVITIES_SETTING,new Map<String,Object>{'newMap' => 'foo'});
            System.assert(true,'We passed the wrong type for newMap. We should never reach this line');
        }
        catch(TypeException ex) {
            System.debug('expected exception: '+ex);
        }
    }
}