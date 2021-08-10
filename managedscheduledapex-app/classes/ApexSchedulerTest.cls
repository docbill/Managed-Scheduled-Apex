// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This class contains unit tests for validating the ApexScheduler class.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * @version 2021-07-27
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2011-09-30 - Created
 * @since 2013-07-30 - Auto-increase concurrent limit to allow this test to succeed
 * @since 2016-01-19 - Added Test_Batchable to avoid dependancies on real batch classes
 * @since 2018-09-12 - Added new params to method calls
 * @since 2020-03-27 US245556 US252351 - Updated to support metadata in tests and correct error in Requalification
 * @since 2020-04-02 US252351 - Updated for active flag
 * @since 2020-04-14 Test Fix - Revert change to insert accountStatusChangeSetting, as this only works in DEV1.
 * @since 2020-04-29 US254090 - Added tests for task owner picklist values
 * @since 2020-12-04 - Removed ScheduledApex__c support
 * @since 2020-12-09 - Renamed from DailySchedulerTest
 * @since 2021-07-27 - Removed references to Task_Owner__c field
 */
@isTest
global class ApexSchedulerTest implements Database.Batchable<SObject> {
    static final String APEX_SCHEDULER_TEST ='ApexSchedulerTest';

    // There are some entries we want to ignore in this test class.
    static {
        ApexScheduler.testRecordPrefix = null;
        for(Scheduled_Apex__mdt sa : [select DeveloperName from Scheduled_Apex__mdt where SkipTestClass__c = true]) {
            ApexScheduler.scheduledTimeMap.remove(sa.DeveloperName);
        }
        ApexScheduler.ScheduledTime st = createScheduledTime(true,APEX_SCHEDULER_TEST,'*','*',null,null,null,null,null);
        ApexScheduler.scheduledTimeMap.put(APEX_SCHEDULER_TEST,st);
    }

    @testSetup
    static void testSetup() {
        ApexScheduler.settings.MaxConcurrentJobs__c = ApexScheduler.CONCURRENT_JOB_LIMIT;
        ApexScheduler.settings.JobName__c = ApexScheduler.DEFAULT_JOB_NAME;
        upsert ApexScheduler.settings;
    }
    
    /**
     * start method impl for Database.Batchable interface
     *
     * @param   Database.BatchableContext bc
     * @return  List<SObject> list of credit objects to expire
     */
    global List<User> start(Database.BatchableContext bc) 
    {
        return new List<User>();
    }

    /** 
     * execute method impl for Database.Batchable interface
     *
     * @param   Database.BatchableContext bc
     * @param   List<SObject> credit objects
     */
    global void execute(Database.BatchableContext bc, List<SObject> objects) {}

    /**
     * finish method impl for Database.Batchable interface
     *
     * @param   Database.BatchableContext bc
     */
    global void finish(Database.BatchableContext bc) {}

    static String quoteValue(String value) {
        if(value != null) {
            value = '"'+value+'"';
        }
        return value;
    }

    @TestVisible
    static ApexScheduler.ScheduledTime createScheduledTime(Boolean isActive,String name,String hour,String minute,Id userId,Decimal scope,Decimal priority,Boolean mustRun,String className) {
        String jsonString = '{'
            +'"Active__c":'+isActive+','
            +'"ClassName__c":'+quoteValue(className)+','
            +'"Hour__c":'+quoteValue(hour)+','
            +'"Minute__c":'+quoteValue(minute)+','
            +'"Task_OwnerId__c":'+quoteValue(String.valueOf(userId))+','
            +'"Scope__c":'+scope+','
            +'"Priority__c":'+priority+','
            +'"MustRun__c":'+mustRun+','
            +'"DeveloperName":'+quoteValue(name)+'}';
        Scheduled_Apex__mdt st = (Scheduled_Apex__mdt)JSON.deserialize(jsonString,Scheduled_Apex__mdt.class);
        return new ApexScheduler.ScheduledTime(st);
    }

    @isTest
    static void isJobActiveTest() {
        ApexScheduler ds = new ApexScheduler(30,6);
        DateTime currentTime = DateTime.newInstance(Date.today(),Time.newInstance(5,0,0,0));
        for(ApexScheduler.ScheduledTime st : new List<ApexScheduler.ScheduledTime>{
                createScheduledTime(true,'Foo1','*','0,30',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo2','5','*',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo3','1-3,4,5,7-9','29,31',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo4','1-9,10-20','0-10,15,25,35,40,50,55',UserInfo.getUserId(),200.0,0.0,true,null)})
        {
            System.assert(ds.isJobActive(currentTime,st),'Failed test with: '+st);
        }
        for(ApexScheduler.ScheduledTime st : (new List<ApexScheduler.ScheduledTime>{
                createScheduledTime(true,'Foo5','-','0,30',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo6','1-3','*',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo7','1-4,10-20','29,31',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo8','20,1-4,10-20','0-10,15,25,35,40,50,55',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo9','*','0,20,40',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo10','5','-',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo11','1-3,4,5,7-9','1-29,40-59',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(true,'Foo12','1-9,10-20','12,24,36,48',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(false,'Foo13','-','0,30',UserInfo.getUserId(),200.0,0.0,true,null),
                createScheduledTime(false,'Foo14','5','-',UserInfo.getUserId(),200.0,0.0,true,null) } ) )
        {
            System.assert(! ds.isJobActive(currentTime,st),'Failed test with: '+st);
        }
    }

    @isTest
    static void executeTest() {
        ApexScheduler.scheduledTimeMap.keySet().retainAll(new Set<String>{APEX_SCHEDULER_TEST});
        // make sure all the following tests work by injection
        ApexScheduler.triggerOptional = false;
        ApexScheduler ds = new ApexScheduler(0,60);
        MonitoredActivity__c ma = new MonitoredActivity__c(
            Subject__c=ApexScheduler.SUBJECT_HEADER+APEX_SCHEDULER_TEST,
            RecordTypeId__c=ApexScheduler.SCHEDULED_TASK_RECORDTYPE_ID,
            SkippedCount__c = 20);
        ApexScheduler.batchNameBySubjectMap.put(ma.Subject__c,APEX_SCHEDULER_TEST);
        // now something that will succeed
        ApexScheduler.injectBatchable(new List<MonitoredActivity__c>{ma},APEX_SCHEDULER_TEST,new Test_Batchable());
        ds.execute(null);
        System.assertEquals('',ds.errorMessageBody,'ds.errorMessageBody');
        Task t = [select Subject from Task where Subject = :ma.Subject__c];
        MonitoredActivity__c ma2 = [select Subject__c from MonitoredActivity__c where TaskId__c = :t.Id];
        System.assertEquals(t.Subject,ma2.Subject__c);

        // now lets try again
        ds = new ApexScheduler(0,60);
        ApexScheduler.batchNameBySubjectMap.put(ma.Subject__c,APEX_SCHEDULER_TEST);
        ApexScheduler.injectBatchable(new List<MonitoredActivity__c>{ma},APEX_SCHEDULER_TEST,new Test_Batchable());
        ds.execute(null);
        System.assertEquals('',ds.errorMessageBody,'ds.errorMessageBody');
        Task t2 = [select Id from Task where Subject = :ma.Subject__c];
        System.assertNotEquals(t.Id,t2.Id);

        // this with reflection instead of injection
        ApexScheduler.triggerOptional = true;
        ds = new ApexScheduler(0,60);
        ds.execute(null);
        System.assertEquals('',ds.errorMessageBody,'ds.errorMessageBody');
        Task t3 = [select Id from Task where Subject = :ma.Subject__c];
        System.assertNotEquals(t2.Id,t3.Id);

        // finally try again, this time a failure case
        ApexScheduler.triggerOptional = false;
        ds = new ApexScheduler(0,60);
        ds.execute(null);
        System.assertEquals('',ds.errorMessageBody,'ds.errorMessageBody');
        Task t4 = [select Id from Task where Subject = :ma.Subject__c];
        System.assertEquals(t3.Id,t4.Id);

        ds = new ApexScheduler(0,60);
        ApexScheduler.batchNameBySubjectMap.put(ma.Subject__c,APEX_SCHEDULER_TEST);
        ApexScheduler.injectBatchable(new List<MonitoredActivity__c>{ma},APEX_SCHEDULER_TEST,new Test_Batchable());
        ApexScheduler.setExcludedSubject(ma.Subject__c,false);
        ApexScheduler.setExcludedSubject(ma.Subject__c,true);
        ds.execute(null);
        System.assertEquals('',ds.errorMessageBody,'ds.errorMessageBody');
    }

    @isTest
    static void submitJobTest() {
        ApexScheduler.ScheduledTime st = ApexScheduler.scheduledTimeMap.get(APEX_SCHEDULER_TEST);
        ApexScheduler ds = new ApexScheduler(0,60);

        // first success
        ApexScheduler.batchableMap.clear();
        ApexScheduler.batchableMap.put(APEX_SCHEDULER_TEST,new Test_BatchableWork());
        ds.submitJobs(null,new Map<String,Id>() );
        System.assertEquals('',ds.errorMessageBody,'ds.errorMessageBody');

        // now failure
        ApexScheduler.batchableMap.clear();
        ApexScheduler.batchableMap.put(APEX_SCHEDULER_TEST,new Test_BatchableWork());
        batchableWorkNumber = 'force failure';
        ds.submitJobs(null,new Map<String,Id>() );
        System.assertNotEquals('',ds.errorMessageBody,'ds.errorMessageBody');
    }

    @isTest
    static void jsonConstructorTest() {
        List<ApexScheduler.ScheduledTime> stList = ApexScheduler.scheduledTimeMap.values();
        stList.sort();
        for(ApexScheduler.ScheduledTime st : stList) {
            if(st.active) {
                try {
                    Object batchable = st.createInstance();
                    System.assertNotEquals(null,batchable,'Failed to create instance for job '+st.name);
                }
                catch(Exception ex) {
                    System.assert(false,'Threw Exception for job '+st.Name+'\n'+ex+'\n'+ex.getStackTraceString());
                }
            }
        }
    }

    @isTest
    static void invokeJobBatchableWorkTest() {
        ApexScheduler.ScheduledTime st = ApexScheduler.scheduledTimeMap.get(APEX_SCHEDULER_TEST);
        Object b = new Test_BatchableWork();
        Id jobId = null;
        Test.startTest();
        jobId = ApexScheduler.invokeJob(null,b,st.name,st.scope);
        Test.stopTest();
        System.assertNotEquals(null,jobId,'ApexScheduler.invokeJob(null,new Testable_BatchableWork(),st)');
    }

    @isTest
    static void invokeJobBatchableTest() {
        ApexScheduler.ScheduledTime st = ApexScheduler.scheduledTimeMap.get(APEX_SCHEDULER_TEST);
        // AbstractBatchable test
        Object b = new ApexSchedulerTest();
        Test.startTest();
        Id jobId = ApexScheduler.invokeJob(null,b,st.name,st.scope);
        Id jobId2 = ApexScheduler.invokeJob(null,jobId,st.name,st.scope);
        Test.stopTest();
        System.assertNotEquals(null,jobId,'ApexScheduler.invokeJob(null,new ApexSchedulerTest(),st)');
        System.assertNotEquals(null,jobId2,'ApexScheduler.invokeJob(null,jobId,st)');
    }

    @isTest
    static void invokeJobQueueableTest() {
        ApexScheduler.ScheduledTime st = ApexScheduler.scheduledTimeMap.get(APEX_SCHEDULER_TEST);
        // AbstractBatchable test
        Object b = new Test_Queueable();
        Test.startTest();
        Id jobId = ApexScheduler.invokeJob(null,b,st.name,st.scope);
        Test.stopTest();
        System.assertNotEquals(null,jobId,'ApexScheduler.invokeJob(null,new Test_Queueable(),st)');
    }

    static Boolean schedulableInvoked = false;

    @isTest
    static void invokeJobSchedulableTest() {
        ApexScheduler.ScheduledTime st = ApexScheduler.scheduledTimeMap.get(APEX_SCHEDULER_TEST);
        // AbstractBatchable test
        Object b = new Test_Schedulable();
        Test.startTest();
        Id jobId = ApexScheduler.invokeJob(null,b,st.name,st.scope);
        Test.stopTest();
        System.assertEquals(true,schedulableInvoked,'ApexScheduler.invokeJob(null,new Test_Schedulable(),st)');
    }

    static String batchableWorkNumber = '1';

    global class Test_BatchableWork implements Nameable, BatchableWork {
        public String name = null;

        public Boolean hasWork() { return true; }

        /**
         * Method to execute this batch job.
         * @param scope the size of this job
         * @return jobId
         */    
        public String executeBatch(Integer scope) {
            return UserInfo.getUserId();
        }

        public void setName(String value) {
            Integer.valueOf(batchableWorkNumber);
            this.name = value;
        }

        public String getName() {
            return name;
        }
    }

    global class Test_Batchable extends AbstractBatchable {
        global Test_Batchable() {
            super('Test_Batchable');
        }

        global List<User> start(Database.BatchableContext bc) {
            return [select Id from User limit 10];
        }

        global void execute(Database.BatchableContext bc, List<User> users) {
        }
    }

    public class Test_Queueable implements Queueable {
        public void execute(QueueableContext context) {}
    }

    public class Test_Schedulable implements Schedulable {
        public void execute(SchedulableContext context) {
            schedulableInvoked = true;
        }
    }

}