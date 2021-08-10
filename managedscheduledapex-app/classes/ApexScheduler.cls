// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * ApexScheduler
 * 
 * This class schedules the batches for any apex jobs designed to run at least once
 * per day.  The Scheduled_Apex__mdt values are used to determine actual 
 * invocation schedule.  To help limit dependancies and ensure notification should 
 * the job fail to run, this class works by updating or creating tasks.  
 * 
 * Normally all the jobs arguments are included in a json constructor. In the cases
 * where the class cannot be directly created and scheduled as a json constructor there
 * are two options.  One is to create a wrapper class that implements the BatchableWork
 * interface.   Make the json contructor simply:
 * <pre>
  * {"_ClassName":"YourClassName"}
 * </pre>
 * 
 * Another option is a Monitored Activities trigger call the ApexScheduler.insertBatchable.
 * The trigger can be as  simple as:
 *
 *  trigger MA_Foo on MonitoredActivity__c (after insert) {
 *      ApexScheduler.injectBatchable(Trigger.new,'Foo',new Foo());
 *  }
 *
 * Should there be more than one task for the job the oldest will be delete
 * on success and the newest on failure.  This way a time based trigger can 
 * be used to notify when the task is significantly over due.
 *
 * If a batchable interferace is extented from AbstractBatchableBase, there is a 
 * skipBatchable method that may be called to determine if the batch may be
 * skipped this iteration (because there is no work to do).  If a batch that is
 * skipped for this reason is treated the same as a batch that ran successfully.
 *
 * @version 2021-07-27
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2011-09-30 - Created
 * @since 2012-06-11 - Updated to use tasks and allow scheduling more than once an hour
 * @since 2013-02-13 - Added stack trace to generic error email
 * @since 2013-07-05 - Added must run logic to process skipped jobs as soon as possible
 * @since 2013-07-30 - Correcting defect.  We must leave at least one jobs slot available.
 * @since 2014-04-21 - Update to use AbstractBatchable
 * @since 2014-04-24 - Refactored for better test coverage
 * @since 2018-02-06 - Attempting to make the trigger optional with a new setting.
 * @since 2018-02-06 - Support a separate class name and name in ScheduledApex__c
 * @since 2018-02-06 - Support batchable, and queuable in the schedule.
 * @since 2018-09-11 Added support for jsonConstructor and invoking other Schedulable classes...
 * @since 2020-02-26 US248556 - Updated to use AbstractBatchableBase
 * @since 2020-03-05 US248556 - Added support for the executeBatch method of AbstractBatchableBase
 * @since 2020-03-12 US248556 - Remevode schedule method
 * @since 2020-03-26 US252351 - Implemented Scheduled_Apex__mdt to replace the custom setting
 * @since 2020-04-02 US252351 - Implemented active flag
 * @since 2020-04-02 US248556 - Use BatchableWork and Nameable interfaces instead of AbstractBatchableBase
 * @since 2020-04-15 US248556 - Added debugging and correct reference to AbstractBatchableBase
 * @since 2020-04-29 DE23242 - Recursively load Scheduled_Apex__c to allow a launcher
 * @since 2020-09-09 US270544 - Use Scheduled_Apex_Setting__c for configuration values
 * @since 2020-09-10 US270544 - Support the Callable interface 'getHasWork' and 'execute' actions
 * @since 2020-12-04 - Support / as part of the range
 * @since 2020-12-04 - Decreciated ScheduledApex__c
 * @since 2020-12-04 - Support day of week and day of month
 * @since 2020-12-09 - Renamed from DailyScheduler
 * @since 2020-12-09 - Added support for jobname
 * @since 2021-07-27 - Removed references to Task_Owner__c field
 */
global class ApexScheduler implements Schedulable {

    @TestVisible
    private static Boolean triggerOptional = true;
    @TestVisible
    private static String testRecordPrefix = 'TEST.';

    // There really should be a Limit method for this value...
    global static Integer CONCURRENT_JOB_LIMIT = 5;
    // This is a code limitation. 
    global static Integer RESERVED_DML = 10;
    // This subject prefix is used to identify our special tasks.
    global final static String SUBJECT_HEADER = 'Scheduled Job Task: ';
    // This is the record type we use for scheduled job tasks.
    global static Id SCHEDULED_TASK_RECORDTYPE_ID {
        get {
            if(SCHEDULED_TASK_RECORDTYPE_ID == null) {
                SCHEDULED_TASK_RECORDTYPE_ID = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('Scheduled_Task').getRecordTypeId();
            }
            return SCHEDULED_TASK_RECORDTYPE_ID;
        }
        private set {}
    }

    public static final String DEFAULT_JOB_NAME {
		get {
            if(DEFAULT_JOB_NAME == null) {
                DEFAULT_JOB_NAME = blankValue(
                    Scheduled_Apex_Settings__c.getOrgDefaults().JobName__c,
                    ApexScheduler.class.getName() );
            }
            return DEFAULT_JOB_NAME;
        }
        set;
	}

    // This is the map which will store the batchable objects
    @TestVisible
    static Map<String,Object> batchableMap = new Map<String,Object>();
    @TestVisible
    static Set<String> excludedSubjects = new Set<String>();
    global static Map<String,String> batchNameBySubjectMap = new Map<String,String>();
    @TestVisible
    Integer startMinute;
    @TestVisible
    Integer frequency;
    @TestVisible
    Set<Id> ownerIds = new Set<Id>();
    @TestVisible
    String errorMessageBody = '';

    /**
     * Constructor which includes scheduling information.
     *
     * @param start how many minute past the hour in which this job has been scheduled to start
     * @param frequency how many minutes until the next time the job runs
     */
    global ApexScheduler(Integer start,Integer frequency) {
        this.startMinute = start;
        this.frequency = frequency;
    }

    global static Scheduled_Apex_Settings__c settings {
		get {
			if(settings == null) {
				settings = Scheduled_Apex_Settings__c.getInstance();
				if(settings.Id == null) {
                    settings.JobName__c = null;
					insert settings;
					settings = Scheduled_Apex_Settings__c.getInstance();
				}
			}
			return settings;
		}
		set;
	} 


    /**
     * Read the maxConcurrentJobsvalue from the custom setting.
     */
    @TestVisible
    static Integer maxConcurrentJobs {
        get {
            if(maxConcurrentJobs == null) {
                Decimal ls = settings.MaxConcurrentJobs__c;
                if(ls != null) {
                    maxConcurrentJobs = ls.intValue();
                }
            }
            return maxConcurrentJobs;
        }
        set;
    }

    @TestVisible
    static Set<String> splitToSet(String value,String sep) {
        Set<String> retval = new Set<String>();
        if(String.isNotBlank(value)) {
            for(String s : value.toUpperCase().split(sep)) {
                if(String.isNotBlank(s)) {
                    retval.add(s.trim());
                }
            }
        }
        return retval;
    }

    @TestVisible
    static Set<String> activeJobStatuses {
        get {
            if(activeJobStatuses == null) {
                activeJobStatuses = splitToSet(settings.ActiveJobStatuses__c,',');
            }
            return activeJobStatuses;
        }
        set;
    }

    @TestVisible
    static Set<String> excludedJobTypes {
        get {
            if(excludedJobTypes == null) {
                excludedJobTypes = splitToSet(settings.ExcludedJobTypes__c,',');
            }
            return excludedJobTypes;
        }
        set;
    }

    /**
     * This method is called from the Task triggers to inject the Database.Batchable<Object>.
     *
     * @param tasks a listing of tasks to process
     * @param batchName the name of the batch being injected
     * @param batchable object to inject
     *
     * @return subject if not previous injected and there is enough reserved queries to to check if there is work to do.
     */ 
    global static String injectBatchable(List<MonitoredActivity__c> monitoredActivities,String batchName,Object batchable) {
        String retval = null;
        try {
            for(MonitoredActivity__c ma : monitoredActivities) {
                if(batchNameBySubjectMap.get(ma.Subject__c) == batchName && ma.RecordTypeId__c == SCHEDULED_TASK_RECORDTYPE_ID) {
                    batchable = batchableMap.put(ma.Subject__c,batchable);
                    if(batchable == null && Limits.getDmlStatements()+RESERVED_DML < Limits.getLimitDmlStatements()) {
                        retval = ma.Subject__c;
                    }
                    break;
                }
            }
        }
        catch(Exception ex) {
            System.debug('Caught:'+ex+'\n'+ex.getStackTraceString());
        }
        return retval;
    }

    /**
     * Called to add or remove a value to the excluded subject set.  This set is used to 
     * by-pass running a job when there is no work to do.
     * @param subject the subject name of the monitored activity
     * @param hasWork false to add to the set, true to remove
     */
    global static void setExcludedSubject(String subject,Boolean hasWork) {
        if(subject != null) {
            if(hasWork == true) {
                excludedSubjects.remove(subject);
            }
            else if(hasWork == false){
                excludedSubjects.add(subject);
            }
        }
    }
    
    static String blankValue(String value, String defaultValue) {
        if(String.isBlank(value)) {
            value = defaultValue;
        }
        return value;
    }

    public static List<Scheduled_Apex__mdt> scheduledApexMetadataList {
        get {
            if(scheduledApexMetadataList == null) {
                scheduledApexMetadataList = [
                    select
                        Active__c,
                        ClassName__c,
                        CronSchedule__c,
                        JobName__c,
                        NamespacePrefix__c,
                        DeveloperName,
                        DayOfWeek__c,
                        DayOfMonth__c,
                        Hour__c,
                        JSON_Constructor__c,
                        JSON_Checksum__c,
                        Minute__c,
                        MasterLabel,
                        Month__c,
                        MustRun__c,
                        Priority__c,
                        Scope__c,
                        Task_OwnerId__c,
                        Task_Owner_Name__c,
                        Year__c,
                        QualifiedApiName
                    from Scheduled_Apex__mdt ];
            }
            return scheduledApexMetadataList;
        }
        set;
    }

    @TestVisible 
    static Map<String,ScheduledTime> scheduledTimeMap {
        get {
            if(scheduledTimeMap == null) {
                scheduledTimeMap = scheduledTimeMapUnfiltered.clone();
                for(String key : scheduledTimeMapUnfiltered.keySet()) {
                    ScheduledTime st = scheduledTimeMap.get(key);
                    if(st.active != true 
                        || st.dayOfWeekRange == '-'
                        || st.dayOfMonthRange == '-'
                        || st.hourRange == '-'
                        || st.minuteRange == '-'
                        || st.jobName != settings.JobName__c )
                    {
                        scheduledTimeMap.remove(key);
                    }
                }
                System.debug('scheduledTimeMap.keySet()='+scheduledTimeMap.keySet());
            }
            return scheduledTimeMap;
        }
        set;

    }

    public static Map<String,ScheduledTime> scheduledTimeMapUnfiltered {
        get {
            if(scheduledTimeMapUnfiltered == null) {
                scheduledTimeMapUnfiltered = new Map<String,ScheduledTime>();
                for(Scheduled_Apex__mdt sa : scheduledApexMetadataList) {
                    if( testRecordPrefix == null || ! sa.MasterLabel.startsWith(testRecordPrefix)) {
                        scheduledTimeMapUnfiltered.put(sa.DeveloperName,new ScheduledTime( sa ));
                    } 
                }
                System.debug('scheduledTimeMapUnfiltered.keySet()='+scheduledTimeMapUnfiltered.keySet());
            }
            return scheduledTimeMapUnfiltered;
        }
        set;
    }

    /**
     * This should only be assigned for test purposes.
     */
    @TestVisible
    DateTime currentDateTimeTestData = null;

    /**
     * Returns the current time.
     */
    @TestVisible
    DateTime getCurrentDateTime() {
        DateTime retval = currentDateTimeTestData;
        if(retval == null) {
            retval = DateTime.now();
        }
        return retval;
    }

    /**
     * Test BatchableFactory if a value is in the active range.
     */
    @TestVisible
    static Boolean isActiveRange(Integer value,Integer endValue,String saRange) {
        Boolean retval = false;
        saRange = (''+saRange).replaceAll('[^-0-9?*/,]','');
        switch on saRange {
            // Both '*' and '?' will match anything'
            when '*', '?' {
                return true;
            }
            when '-', '' {
                return false;
            }
            when else {
                saRange = saRange.replaceAll('[*?]','0');
                if(value < 0) {
                    value = 0;
                }
                // find out if the job is scheduled during this time frame
                for(;value < endValue;value++) {
                    // the range can be comma separeted expressions
                    for(String range : saRange.split(',')) {
                        if(String.isNotBlank(range)) {
                            // each expression can be a range
                            String [] incArray = range.split('/',2);
                            String [] rangeArray = incArray[0].split('-',2);
                            if(String.isNotBlank(rangeArray[0])) {
                                Integer inc = 0;
                                if(incArray.size() > 1 && incArray[1].isNumeric()) {
                                    inc = Integer.valueOf(incArray[1]);
                                }
                                if(inc < 1) {
                                    inc = endValue+1;
                                }
                                Integer startTime = 0;
                                if(rangeArray[0].isNumeric()) {
                                    startTime = Integer.valueOf(rangeArray[0]);
                                }
                                Integer endTime = startTime;
                                if(rangeArray.size() > 1 && rangeArray[1].isNumeric()) {
                                    endTime = Integer.valueOf(rangeArray[1]);
                                }
                                if(startTime <= endTime) {
                                    while(startTime < endValue) {
                                        if(startTime <= value && value <= endTime) {
                                            return true;
                                        }
                                        startTime+=inc;
                                        endTime+=inc;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return retval;
    }

    /**
     * Test if a className is scheduled to run at this time.
     */
    @TestVisible
    Boolean isJobActive(DateTime currentTime,ScheduledTime st) {
        final Date currentDate = currentTime.date();
        final Integer year = currentDate.year();
        final Integer month = currentDate.month();
        final Integer dayOfWeek = Math.mod(Date.newInstance(1999,12,26).daysBetween(currentDate),7)+1;
        final Integer dayOfMonth = currentDate.day();
        final Integer hour = currentTime.hour();
        return st.active 
            && isActiveRange(year,year+1,st.yearRange)
            && isActiveRange(month,month+1,st.monthRange)
            && isActiveRange(dayOfMonth,dayOfMonth+1,st.dayOfMonthRange)
            && isActiveRange(hour,hour+1,st.hourRange)
            && isActiveRange(startMinute,startMinute+frequency,st.minuteRange);
    }

    /**
     * execute method impl for Schedulable interface
     *
     */
    global void execute( SchedulableContext sc ) {
        Map<Id,Id> jobIdMap = null;
        try {
            Map<String,Id> taskIdMap = new Map<String,Id>();
            try {
                taskIdMap = prepareJobs( );
                jobIdMap = submitJobs(sc,taskIdMap);
            }
            catch(Exception e) {
                System.debug(e);
                errorMessageBody += 'Caught Exception: \n'+e.getStackTraceString();
            }
            finally {
                try {
                    deleteOldTasks( taskIdMap );
                }
                finally {
                    mailErrorMessage();
                }
            }
        }
        finally {
            errorMessageBody = '';
            ownerIds.clear();
            batchNameBySubjectMap.clear();
            batchableMap.clear();
            excludedSubjects.clear();
            // update all the monitored activies with the new job ids.
            if(jobIdMap != null && ! jobIdMap.isEmpty()) {
                List<MonitoredActivity__c> monitoredActivities = [
                    select TaskId__c
                    from MonitoredActivity__c
                    where TaskId__c in :jobIdMap.keySet() ];
                for(MonitoredActivity__c ma : monitoredActivities) {
                    Id jobId = jobIdMap.remove(ma.TaskId__c);
                    // excluded jobs won't have a new job id, so retain the old value
                    if(jobId != null) {
                        ma.AsyncApexJobId__c = jobId;
                    }
                }
                Database.update(monitoredActivities,false);
            }
        }
    }

    /**
     * Called to fill the skippedMap and lastRunMap.
     * 
     * @param skippedMap map to be filled with monitored activities that have been skipped.
     * @param lastRunMap map filled with monitored activies that have not been skipped.
     * @return map of monitored activites
     */
    @TestVisible
    Map<Id,MonitoredActivity__c> getMonitoredActivityMap(
        Map<String,MonitoredActivity__c> skippedMap,
        Map<String,MonitoredActivity__c> lastRunMap)
    {
        Map<Id,MonitoredActivity__c> monitoredActivityMap = new Map<Id,MonitoredActivity__c>();
        for(MonitoredActivity__c ma : [
            select AsyncApexJobId__c, SkippedCount__c, Subject__c, Task__c
            from MonitoredActivity__c
            where Subject__c like :SUBJECT_HEADER+'%' ])
        {
            if(ma.AsyncApexJobId__c != null) {
                monitoredActivityMap.put(ma.AsyncApexJobId__c,ma);
            }
            Map<String,MonitoredActivity__c> bySubjectMap = lastRunMap;
            if(ma.SkippedCount__c != null && ma.SkippedCount__c > 0) {
                bySubjectMap = skippedMap;
            }
            bySubjectMap.put(ma.Subject__c,ma);
        }
        return monitoredActivityMap;
    }

    /**
     * Called fill the status map of AsyncApexJobs and count how many are still active.
     * 
     * @param monitoredActivityMap map of monitored activides by job id
     * @param statusMap map to fill with job status
     * @return count of number of active jobs
     */
    @TestVisible
    Integer getActiveCount(Map<Id,MonitoredActivity__c> monitoredActivityMap,Map<String,String> statusMap) {
        Integer activeCount = 0;
        Map<Id,String> statusByClassIdMap = new Map<Id,String>();
        for(AsyncApexJob job : [
            select Status, ApexClassId
            from AsyncApexJob
            where Id in :monitoredActivityMap.keySet()
                or (Status in :activeJobStatuses and JobType not in :excludedJobTypes) ] )
        {
            if(job.Status != null) {
                MonitoredActivity__c ma = monitoredActivityMap.get(job.Id);
                if(ma != null) {
                    statusMap.put(ma.Subject__c,job.Status);
                }
                else {
                    statusByClassIdMap.put(job.ApexClassId,job.Status);
                }
                if(activeJobStatuses.contains(job.Status.toUpperCase())) {
                    activeCount++;
                }
            }
        }
        if(! statusByClassIdMap.isEmpty()) { 
            for(ApexClass ac : [
                select Id, Name
                from ApexClass
                where Id in :statusByClassIdMap.keySet() ] )
            {
                statusMap.put(('class='+ac.Name).toLowerCase(),statusByClassIdMap.get(ac.Id));
            }
        }
        System.debug('activeCount='+activeCount);
        return activeCount;
    }

    /**
     * Called to create all the neccessary tasks.
     * 
     * @param taskIdMap map to fill with all the newly created tasks
     * @param currentTime timestamp to use for queueing requests
     * @param stSorted a sorted list of scheduledtimes
     * @param statusMap a map with the status of jobs
     * @param skippedMap a map of jobs that have been previously skipped
     * @param lastRunMap a map of jobs that have not been previously skipped
     * @param jobsRemaining the maximum number of jobs we can add to the queue
     * @param scheduledTimeMap a map of jobs that can be scheduled
     * @return the savePoint if we have too many jobs queued up.
     */
    @TestVisible
    Savepoint prepareTasks(
        Savepoint savePoint,
        Map<String,Id> taskIdMap,
        final DateTime currentDateTime,
        List<ScheduledTime> stSorted,
        Map<String,String> statusMap,
        Map<String,MonitoredActivity__c> skippedMap,
        Map<String,MonitoredActivity__c> lastRunMap,
        Integer jobsRemaining  )
    {
        taskIdMap.clear();
        skippedMap = skippedMap.clone();
        List<Task> tasks = new List<Task>();
        List<MonitoredActivity__c> skippedActivities = new List<MonitoredActivity__c>();
        Map<String,ScheduledTime> scheduledTimeBySubject = new Map<String,ScheduledTime>();
        for(ScheduledTime st : stSorted) {
            System.debug('prepareTasks:ScheduledTime='+st.Name+',jobsRemaining='+jobsRemaining);
            String subject = SUBJECT_HEADER+st.Name;
            scheduledTimeBySubject.put(subject,st);
            String status = statusMap.get(('class='+st.fullClassName).toLowerCase());
            if(status == null) {
                status = statusMap.get(subject);
            }
            try {
                MonitoredActivity__c skippedActivity = skippedMap.remove(subject);
                Object batchable = batchableMap.remove(subject);
                if(isJobActive(currentDateTime,st) || (st.mustRun && skippedActivity != null)) {
                    // We don't run excluded jobs, but we will update the tasks as if we ran them
                    // Unfortunately, excluded will always be false the first time through.
                    Boolean excluded = excludedSubjects.contains(subject);
                    if( savePoint != null || (( batchable != null) && ( excluded || jobsRemaining > 0 )) ) {
                        // if there is no savePoint, then we need to keep track of jobs as there is no undo 
                        // when too many end-up queued.
                        if(savePoint == null && ! excluded) {
                            jobsRemaining--;
                        }
                        if(status == null || status == 'Completed' || status == 'Aborted' || status == 'Failed')
                        {
                            batchNameBySubjectMap.put(subject,st.Name);
                            DateTime reminderDateTime = currentDateTime.addDays(1).addMinutes(frequency);
                            if(st.dayOfMonthRange != '*' && st.dayOfMonthRange != '?') {
                                reminderDateTime = reminderDateTime.addDays(Date.daysInMonth(currentDateTime.year(),currentDateTime.month())-1);
                            }
                            else if(st.dayOfWeekRange != '*' && st.dayOfWeekRange != '?') {
                                reminderDateTime = reminderDateTime.addDays(6);
                            }
                            tasks.add(new Task(
                                ActivityDate = reminderDateTime.date(),
                                IsReminderSet = true,
                                ReminderDateTime = reminderDateTime,
                                Monitor__c = true,
                                OwnerId=st.OwnerId,
                                RecordTypeId = SCHEDULED_TASK_RECORDTYPE_ID,
                                Subject=subject));
                            if(batchable != null) {
                                batchableMap.put(subject,batchable);
                            }
                        }
                        // Normally jobs should complete by the next scheduled start time...
                        if(savePoint == null && (status == 'Processing' || status == 'Failed')) {
                            errorMessageBody += 'Job status '+status+' for '+st.Name+'\n\n';
                            ownerIds.add(st.OwnerId);
                        }
                    }
                    else if( st.mustRun ) {
                        // we can't run an activity that must be run, so we'll update the activity
                        // so it will return the the queue again next time
                        if(skippedActivity == null) {
                            // skipping this activity
                            skippedActivity = lastRunMap.get(subject);
                        }
                        if(skippedActivity.SkippedCount__c == null || skippedActivity.SkippedCount__c == 0) {
                            skippedActivity.SkippedCount__c = 1;
                        }
                        else {
                            skippedActivity.SkippedCount__c = skippedActivity.SkippedCount__c + 1;
                        }
                        skippedActivities.add(skippedActivity);
                    }
                }
            }
            catch(Exception e) {
                System.debug(e);
                errorMessageBody += 'Error parsing range for '+st.Name+':\n'+e+'\n\n';
                ownerIds.add(st.OwnerId);
            }
        }
        // update skipped activities
        if(! skippedActivities.isEmpty()) {
            Database.update(skippedActivities,false);
        }
        Map<Id,Task> newTaskMap = new Map<Id,Task>();
        // insert the new tasks
        for(Database.SaveResult sr : Database.insert(tasks,false)) {
            Task t = tasks.remove(0);
            if(sr.isSuccess()) {
                taskIdMap.put(t.Subject,t.Id);
                newTaskMap.put(t.Id,t);
            }
            else if(! sr.isSuccess()) {
                String className = batchNameBySubjectMap.remove(t.Subject);
                String e = 'Failed to insert '+t+':\n'+sr.getErrors();
                System.debug(e);
                errorMessageBody += e+'\n\n';
            }
        }
        taskAfterInsert(newTaskMap);

        if(triggerOptional) {
            // this is to make the monitored trigger optional
            for(String subject : taskIdMap.keySet()) {
                if(! batchableMap.containsKey(subject)) {
                    ScheduledTime st = scheduledTimeBySubject.get(subject);
                    if(batchNameBySubjectMap.containsKey(subject) && st != null) {
                        try {
                            System.debug('Create instance: '+subject);
                            Object batchable = st.createInstance();
                            batchableMap.put(subject,batchable);
                            Boolean hasWork = null;
                            try {
                                if(batchable instanceof BatchableWork) {
                                    BatchableWork ab = (BatchableWork)batchable;
                                    hasWork = ((BatchableWork)batchable).hasWork();
                                }
                                else if(batchable instanceof Callable) {
                                    hasWork = (Boolean)((Callable)batchable).call('getHasWork',null);
                                }
                            }
                            catch(Exception ex) {
                                String e= 'Has Work failed '+st.Name+': '+ex;
                                System.debug(e);
                                if(batchable instanceof BatchableWork) {
                                    errorMessageBody += e+'\n\n';
                                }
                            }
                            if(hasWork != null) {
                                System.debug('hasWork check='+hasWork);
                                setExcludedSubject(subject,hasWork);
                            }
                        }
                        catch(Exception ex) {
                            String e= 'Failed to create '+st.Name+': '+ex;
                            System.debug(e);
                            errorMessageBody += e+'\n\n';
                        }
                    }
                }
            }
        }

        // if we succeeded in queuing everything needed, clear the savePoint,
        // as there is no need for an undo.
        if(batchableMap.size()-excludedSubjects.size() <= jobsRemaining) {
            savePoint = null;
        }
        return savePoint;
    }

    /**
     * Called to delete and upsert MonitoredActivity__c objects.
     */
    @TestVisible
    void taskAfterInsert(Map<Id,Task> newMap) {
        List<Task> taskList = new List<Task>();
        List<MonitoredActivity__c> monitoredActivityList = new List<MonitoredActivity__c>();
        Set<String> subjects = new Set<String>();
        for(Task t : newMap.values()) {
            if(t.Monitor__c == true) {
                subjects.add(t.Subject);
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
        if(! monitoredActivityList.isEmpty()) {
            // We do not allow more than one monitored activity per subject
            Database.delete([
                select Id
                from MonitoredActivity__c
                where Subject__c in :subjects
                    and TaskId__c not in :newMap.keySet() ],false);
            // insert new records and update existing ones
            Database.upsert(monitoredActivityList,MonitoredActivity__c.Fields.TaskId__c,false);
        }
    }

    /**
     * Called to delete MonitoredActivity__c objects.
     */
    @TestVisible
    void taskAfterDelete(Set<Id> taskIds) {
        if(! taskIds.isEmpty()) {
            List<Task> taskList = new List<Task>();
            // for now we are ignoring delete errors, leaving orphaned records
            List<MonitoredActivity__c> monitoredActivities = [
                select TaskId__c
                from MonitoredActivity__c
                where TaskId__c in :taskIds];
            Database.delete(monitoredActivities,false);
        }
    }

    /**
     * Called to prepare all the jobs.
     * 
     * @param jobIdMap
     * @return map filled with newly created tasks by subject.
     */
    @TestVisible
    Map<String,Id> prepareJobs( ) {
        // find the job statuses
        Map<String,MonitoredActivity__c> skippedMap = new Map<String,MonitoredActivity__c>();
        Map<String,MonitoredActivity__c> lastRunMap = new Map<String,MonitoredActivity__c>();
        // We need to kee track of the number of concurrent jobs manually
        Map<String,String> statusMap = new Map<String,String>();
        Integer jobsRemaining = maxConcurrentJobs - getActiveCount(getMonitoredActivityMap(skippedMap,lastRunMap),statusMap);
        //System.debug('Jobs Remaining: '+jobsRemaining);
        // examine the schedule and add tasks for jobs ready to run

        Map<String,Id> taskIdMap = new Map<String,Id>();
        List<ScheduledTime> stSorted = scheduledTimeMap.values();
        stSorted.sort();
        Savepoint savePoint = null;
        final DateTime currentTime = getCurrentDateTime();
        if(jobsRemaining > 0) {
            // First try quering up everything available
            try {
                savePoint = Database.setSavepoint();
                savePoint = prepareTasks(savePoint,taskIdMap,currentTime,stSorted,statusMap,skippedMap,lastRunMap,jobsRemaining);
            }
            finally {
                if(savePoint != null) {
                    Database.rollback(savePoint);
                    batchNameBySubjectMap.clear();
                }
            }
        }
        // if we have too many jobs we need to repeat the process this time
        // removing lower priority jobs from our list
        if(savePoint != null || jobsRemaining <= 0) {
            prepareTasks(null,taskIdMap,currentTime,stSorted,statusMap,skippedMap,lastRunMap,jobsRemaining);
        }
        return taskIdMap;
    }


    /**
     * submit jobs
     *
     * @return map of newly submitted job ids by task id
     */
    @TestVisible
    Map<Id,Id> submitJobs(SchedulableContext sc, Map<String,Id> taskIdMap ) {
        Map<Id,Id> jobIdMap = new Map<Id,Id>();
        // process the batchable instances created by the task triggers
        for(String subject : batchableMap.keySet()) {
            ScheduledTime st = scheduledTimeMap.get(subject.removeStartIgnoreCase(SUBJECT_HEADER));
            try {
                Object b = batchableMap.remove(subject);
                Id jobId = null;
                // We attempt to submit the job with b is null, just so test coverage can 
                // capture this error with an exception.
                System.debug('Execute subject='+subject);
                if(! excludedSubjects.contains(subject)) {
                    if(b instanceof Nameable) {
                        ((Nameable)b).setName( st.name );
                    }
                    if(sc != null || b == null) {
                        jobId = invokeJob(sc,b,st.name,st.scope);
                    }
                }
                batchNameBySubjectMap.remove(subject);
                // Anything left in the map will be removed if there
                // is an older task left.  So remove this map entry.
                jobIdMap.put(taskIdMap.remove(subject),jobId);
            }
            catch(Exception e) {
                System.debug(e);
                String className = batchNameBySubjectMap.remove(subject);
                errorMessageBody += 'Error Invoking '+className+':\n'+e+'\n\n';
                ownerIds.add(st.OwnerId);
            }
        }
        return jobIdMap;
    }

    @TestVisible
    static Id invokeJob(SchedulableContext sc,Object b,String name,Integer scope) {
        Id jobId = null;
        String instanceType = 'Callable';
        try {
            try {
                jobId = (Id)((Callable)b).call('execute',new Map<String,Object>{'name'=>name,'scope'=>scope});
            }
            catch(Exception ex) {
                instanceType = 'none';
                if(b instanceof BatchableWork) {
                    instanceType = 'BatchableWork';
                    BatchableWork bw = (BatchableWork)b;
                    jobId = bw.executeBatch(scope);
                }
                else if(b instanceof Database.Batchable<SObject>) {
                    instanceType = 'Database.Batchable<SObject>';
                    jobId = Database.executeBatch((Database.Batchable<SObject>)b,scope);
                }
                else if(b instanceof Queueable) {
                    instanceType = 'Database.Batchable<SObject>';
                    jobId = System.enqueueJob((Queueable)b);
                }
                else if(b instanceof Schedulable) {
                    instanceType = 'Schedulable';
                    System.debug('Schedulable Start');
                    Schedulable s = (Schedulable)b;
                    s.execute(sc);
                }
                else if(b instanceof Id) {
                    instanceType = 'TrackedJobId';
                    jobId = (Id)b;
                }
            }
        }
        finally {
            System.debug('Invoked: '+instanceType+': '+b+',jobId='+jobId);
        }
        return jobId;
    }

    /**
     * Delete all but the most recent task for each subject if the task was assigned a job id or
     * excluded.  Otherwise delete all but the second most recent task.
     * 
     * @param taskIdMap map of newly inserted tasks which were not assigned a job id.
     */
    @TestVisible
    void deleteOldTasks( Map<String,Id> taskIdMap ) {
        if(taskIdMap != null) {
            Set<Id> taskIds = new Set<Id>();
            // Find tasks to delete
            for( Task t : [
                select Subject from Task
                where Subject like :SUBJECT_HEADER+'%'
                    and RecordTypeId = :SCHEDULED_TASK_RECORDTYPE_ID
                    and Id not in :taskIdMap.values()
                order by CreatedDate ] )
            {
                taskIds.add(taskIdMap.get(t.Subject));
                // Add this task id to the map.
                // If there is a newer task selected with the same
                // subject this task will be deleted.
                taskIdMap.put(t.Subject,t.Id);
            }
            taskIds.remove(null);
            Database.delete(new List<Id>(taskIds),false);
            taskAfterDelete(taskIds);
        }
    }

    /**
     * send an email with error messages
     *
     */
    @TestVisible
    void mailErrorMessage( ) {
        // If there are any users, send a failure notification
        if(errorMessageBody != '' || ! batchNameBySubjectMap.isEmpty()) {
            // report any classes which were not created by triggers
            for(String batchName : batchNameBySubjectMap.values()) {
                ScheduledTime st = scheduledTimeMap.get(batchName);
                errorMessageBody += 'Trigger failed to create '+batchName+'\n\n';
                if(st != null) {
                    ownerIds.add(st.OwnerId);
                }
            }
            Set<String> toAddresses = new Set<String>{ 'sf-error-list@redhat.com' };
            if(! ownerIds.isEmpty()) {
                for(User u : [select Email from User where Id in :ownerIds and Email <> null]) {
                    toAddresses.add(u.Email);
                }
            }
            //TODO: uncomment this code when we can turn on email
            //Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            //mail.setToAddresses( new List<String>(toAddresses) );
            //mail.setSubject('Daily Scheduler failure when run as '+UserInfo.getUserName());
            //mail.setPlainTextBody( errorMessageBody );
            //Messaging.sendEmail( new Messaging.SingleEmailMessage[] { mail } );
        }
    }

    public static String rangeString(String value,String defaultValue) {
        if(String.isBlank(value)) {
            value = defaultValue;
        }
        return value.toUpperCase().toUpperCase()
            .replaceAll('[^-,*?/0-9A-Z]','')
            .replaceAll(',,+',',');
	}

    public class ScheduledTime implements Comparable {
        public final Boolean active;
        public final String name;
        public final String className;
        public final String namespacePrefix;
        final Id ownerId;
        final String dayOfMonthRange;
        final String dayOfWeekRange;
        final String hourRange;
        final String minuteRange;
        final String monthRange;
        final String yearRange;
        public final Integer scope;
        public final Double priority;
        final Boolean mustRun;
        final String jsonConstructor;
        final String fullClassName;
        final String jobName;

        @TestVisible
        ScheduledTime(Scheduled_Apex__mdt sa) {
            this.active = (sa.Active__c != false);
            this.name = sa.DeveloperName;
            this.className = blankValue(sa.ClassName__c,sa.DeveloperName).trim();
            this.namespacePrefix = sa.NamespacePrefix__c;
            String dayOfWeek = 
            this.yearRange = rangeString(sa.Year__c,'*');
            this.monthRange = rangeString(sa.Month__c,'*')
                .replace('JAN','1')
                .replace('FEB','2')
                .replace('MAR','3')
                .replace('APR','4')
                .replace('MAY','5')
                .replace('JUN','6')
                .replace('JUL','7')
                .replace('AUG','8')
                .replace('SEP','9')
                .replace('OCT','10')
                .replace('NOV','12')
                .replace('DEC','12');
            this.dayOfWeekRange = rangeString(sa.DayOfWeek__c,'*')
                .replace('MON','1')
                .replace('TUE','2')
                .replace('WED','3')
                .replace('THU','4')
                .replace('FRI','5')
                .replace('SAT','6')
                .replace('SUN','7');
            this.dayOfMonthRange = rangeString(sa.DayOfMonth__c,'*');
            this.hourRange = rangeString(sa.Hour__c,'-');
            this.minuteRange = rangeString(sa.Minute__c,'-');
            Id ownerId = UserInfo.getUserId();
            String taskOwnerId = sa.Task_OwnerId__c;
            if(String.isNotBlank(taskOwnerId)) {
                try {
                    ownerId = taskOwnerId;
                }
                catch(Exception ex) {}
            }
            this.ownerId = ownerId;
            Integer scope = 200;
            if(sa.Scope__c != null) {
                scope = sa.Scope__c.intValue();
            }
            this.scope = scope;
            Double priority = 0.0;
            if(sa.Priority__c != null) {
                priority = sa.Priority__c.doubleValue();
            }
            this.priority = priority;
            this.mustRun = (sa.MustRun__c == true);
            this.jsonConstructor = blankValue(sa.JSON_Constructor__c,'').trim().replace('\n',' ');
            String fullClassName = this.className;
            if( String.isNotBlank(this.className) && String.isNotBlank(this.namespacePrefix)) {
                fullClassName = this.namespacePrefix+'.'+this.fullClassName;
            }
            this.fullClassName = fullClassName;
            this.jobName = blankValue(sa.JobName__c,DEFAULT_JOB_NAME);
        }

        public Integer compareTo(Object compareTo) {
            Integer retval = -1;
            if(compareTo instanceOf ScheduledTime) {
                final ScheduledTime st = (ScheduledTime)compareTo;
                if(this.priority > st.priority) {
                    retval = 1;
                }
                else if(this.priority == st.priority) {
                    if(this.name > st.name) {
                        retval = 1;
                    }
                    else if(this.name == st.name) {
                        retval = 0;
                    }
                }
            }
            return retval;
        }
        
        @TestVisible
        Object createInstance() {
            Object retval = null;
            String fullClassName = this.fullClassName;
            if(String.isNotblank(jsonConstructor)) {
                Map<String,Object> m = (Map<String, Object>)JSON.deserializeUntyped(jsonConstructor);
                fullClassName = blankValue(String.valueOf(m.get('_ClassName')),this.fullClassName);
            }
            if(String.isNotBlank(fullClassName)) {
                System.debug('fullClassName='+fullClassName);
                System.Type t = System.Type.forName(fullClassName);
                if(String.isBlank(jsonConstructor)) {
                    retval = t.newInstance();
                }
                else {
                    retval = JSON.deserialize(jsonConstructor,t);
                }
            }
            return retval;
        }
    }
}