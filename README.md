# Managed Scheduled Apex: Apex Scheduler Usages and Best Practices

## Overview


As developers, salesforce allows us to deploy apex code that is scheduled to run on a regular basis.   This feature is intended to alleviate the need to run separate cron servers connecting into salesforce to do routine code updates.   Unfortunately, while this feature is very powerful, it is also very limited.   Some of the important limits are:

1. No more than 100 jobs can be scheduled per organization.
2. No more than 5 of those jobs can be processing or queued at concurrently.
3. Each job may be scheduled no more than once an hour, otherwise it counts as a separate job for #1.
4. There is no alert mechanism to notify administrators when a scheduled job consistently fails to be queued at it's scheduled time.
5. A class that is scheduled to run may not be update without first removing it from the schedule.
6. These restrictions can cause sever loss of stability with jobs not running and nobody knowing they aren't running until it becomes a customer reported problem.

The ApexScheduler class is an implementation of the Scheduable interface, designed to help us work within the salesforce limitations in a consistent manner.  The ApexScheduler class is designed to use multiple instances of the job slots so that it can invoke our Database.Batchable<SObject> interfaces more than once an hour.  It uses the ScheduledApex__mdt custom metadata so each job can have it's own unique schedule across these invocations.  Tasks and time based workflows are used to supply a minimum level of monitoring.

In the sections that follow we will cover how to configure code to use the Daily Scheduler and some of the best practices in writing apex code for scheduling.

## Configuration
 
In theory any class that implements the Database.Batchable<SObject> , Queueable, or Scheduable interfaces may be used with the Daily Scheduler.   However, it is strongly preferred to use classes that extend AbstractBatchable.   Furthermore, it would be best the ApexScheduler was the only Scheduable interface assigned to the jobs slots.   The reason why it is best not to schedule other jobs directly with the Scheduable interface, is it makes it easier to manage the limitations of salesforce.  Only 5 scheduled jobs can run concurrently.  When more than 5 jobs are scheduled, either we don't run all the scheduled jobs, or add additional jobs to the flex queue.   Should salesforce queue one of those jobs before the ApexScheduler, the ApexScheduler will just have to manage with fewer concurrent slots available.  Should the ApexScheduler run first, it is possible the ApexScheduler will use all 5 concurrent slots and leave no slots available for remaining jobs.

### Configuration: JSON Deserialization Method

There are two to configure a job to run in the daily scheduler.  The first is just to create the Scheduled_Apex__mdt custom metadata and rely on JSON deserialization create the object at scheduled time.  The default JSON constructor is '{}'.  (If you use no constructer instead a forname call will be used for a new instance.)  The JSON constructor will assign null to all your class fields.  If your class works that way, you are good to go.   If your class needs values assign to the fields there are several solutions.

1. Use getters to assign default initial values.  
```
    global String myValue {
         get {
              if(myValue == null) {
                   myValue = <myDefaultValue>;
              }
         }
         set;
    }
```
2. Assign in a method such as start.
3. Specify the value in your JSON constructor.

In most cases we recommend doing both 1 and 3.  Assign a meaningful default in your code, but then assign the value you really want in the json constructor.

### Configuration: MonitoredActivity__c Trigger Method (@Depreciated)
 
The next way to make the job schedulable is to add a trigger  to the MonitoredActivity__c object.  This method of creating an object will not be supported in the future.
You can pass any arguments you need into the new operator for your class constructor.   However, please keep in mind the current implementation is to invoke this trigger every time the Daily Scheduler runs, so you should not do a significant amount of processing in the object constructor.  Your hasWork method will be called every time your job is scheduled to run.  So you'll want to limit your queries in this method, again to help avoid governor limit problems.
 
### Configuration: Scheduled Apex Custom Setting
 
Once you trigger is active, the next step is to actually schedule your class.   We have the Scheduled_Apex__mdt custom object for the purposes of scheduling.   The following lists the available fields:

Scheduled_Apex__mdt FIELDS:

| Field Name | Description              |Example Value |
|:-----------|:------------------------ |:----------   |
| Active__c  | Check when the job is eligible to run. | [x] |
| CronSchedule__c | Auto populated with the schedule in a cron format, for a more concise list view. | ```45 3 * * ? *``` |
| Hour__c    | What time of day to run this task. Allowed values are a number 0 through 23, a range like 6-12, comma separated values or ranges, or * which is equivalent to 0-23.  Lastly a - may be used to indicate the job should not run. One may use a /# to indicate a repeat schedule on the value or range. | 0,1,12-14,25/30 |
| Minute__c | The minute ranges in which the job should invoke.  Like Hour__c can be set to a list of range and values.  * means every time Daily Scheduler runs. One may use a /# to indicate a repeat schedule on the value or range.| 0,6,30-45 |
| DayOfWeek__c | Day of week formatted like a crontab entry.  Comma separated values, with a * as wildcard. | 3 | 
| DayOfMonth__c | Day of month formatted like a crontab entry.  Comma separated values, with a * as wildcard. | 1,15 |
| Month__c | Set to a range of the month. A * may be used as a wildcard. | 0,6,9-12 |
| Year__c | Set to a range of years. A * may be used as a wildcard. | 2022,2030-2045 |
| MasterLabel | This is the name of of the job.  Normally, this can be any unique value in the table, but good default value to use is the class name. | pse.TimecardManager |
| Task_OwnerId__c__c | The salesforce Id of the user who will be notified if the job fails to run. | 00560000000mStZ |
| Task_OWner_Name__c | Auto populated with name from the Task_OwnerId__c | Bill Riemers |
| Priority__c	| This is the relative ranking of the jobs priority.  Should multiple jobs be scheduled for the same time, the job with the lowest priority value is started first.  If all five concurrent slots are used, and there are still jobs left to scheduled, those jobs will not be scheduled.  For this reason, jobs scheduled with the lowest frequency should be given the lowest ranking values.<br>The code itself is not restricted on what priority values may be used, but is the standard we are using in the C360 environment.<br>1.0 - 9.9 :  Used for jobs that are scheduled to run only once or twice a day.<br>10 - 99 : Used for jobs schedule to run no more frequently than twice an hour.<br>100 - 999 : Used for jobs scheduled to run many times an hour that implement the hasWork method to limit how often the actually run.<br>1000 - 9999 : Used for all other jobs.| 23 |
| Scope__c | This is the number of records sent to each individual batch execution, provided your batchable job return a QueryLocator.  Values from 1 to 2000 are supported. | 200 |
| MustRun__c | This is a flag to indicate if job misses it's regularly schedule run time do to the limits on number of concurrent jobs to keep trying to run it until it runs.  We  do not recommend this flag on jobs that scheduled many times an hour, as generally this won't cause the job to run more frequently, but it will cause more job already running e-mail messages to be sent via e-mail. | [ ] |
| NamespacePrefix__c | Used to indicate what namespace the class is part of. | pse |
| ClassName__c	| The name of the class to be created.  If null, we will assume the Name of this record is the class name. | TimecardManager |
| JSON_Constructor__c | This is the string to pass to the JSON deserialization.	|```{```<br>```    "lastProcessedKey":"RPLineSummary.Cleanup",```<br>```    "fromObject": "RenewalProductLineSummary__c",```<br>```    "criterias": [<br>"SystemModStamp >= :LAST_PROCESSED",```<br>```    "PotentialTotalBookingRollUp__c = 0",```<br>```    "ActualTotalBookingRollUp__c = 0",```<br>```    "Id NOT IN (SELECT RenewalProductLineSummary__c FROM OpportunityLineItemClone__c)",```<br>```    "Id NOT IN (SELECT RenewalProductLineSummary__c FROM ExpiringProductForecast__c)" ]```<br>```}``` |
| JSON_Checksum__c | Auto populated with the checksum of the json code when successfully deserialised, or an error message. | HsYCJ+YOoku4Ao7sXfYizg== |
| JobName__c | This is an alternative name for your Apex Job Schedule.  Use this when you want to run as a user other than the default user. | ApexJobsForBriemers |
| SkipTestClass__c | Check this flag to avoid having the this line parsed when test classes run. | [x] |

There currently are no provisions to handle jobs that need to run less frequently than once a day in the schedule.   However, these jobs can be accommodated by a hasWork method that checks day of the week, or month.

## Example Schedule

| Name | Priority (Sorted Ascending) | Hour | Minute | Must Run | Scope | NamespacePrefix | Class Name |
|:-----|:---------------------------:|:-----|:-------|:------:|:------:|:----------------|:---------------|
| pse.UpdateProjectMonitorFieldsBatch | 0.0	| -	| 0 | [x] | 200 | pse | UpdateProjectMonitorFieldsBatch |
| pse.ResourceScheduleManager	| 0.0 | -	| 0	| [ ] | 200	| pse | ResourceScheduleManager |
| pse.TimecardManager | 0.0 | - | 0 | [ ] | 200 | pse | TimecardManager |
| CreditCheck_Expiration | 1.0 | 3 | 0 |[x] | 2,000 |
| Renewal_AutoClosure | 2.0 | 4 | 45 | [x] | 2,000 |
| AddChatterGroupMembersBatchable | 3.0 | 3 | 45 | [x] | 2,000 |
| OpportunityProductSummary | 5.0 | 20 | 0 | [x] | 2,000 | 
| StrategicPlan_OppProdSummary | 6.0 | 23 | 0 | [x] | 2,000 | 
| CampaignStatus_Batchable | 7.0 | 1 | 0 | [x] | 2,000 |
| Opportunity_ProofOfConcept_Batchable | 8.0 | 0 | 10 | [x] | 2,000 |	 
| psaSendMailforEAC | 8.1 | 6 | 0 | [x] | 2,000 | psaSendMailforEAC |
| psaSendMailForEffectiveBillRateUpdate | 8.2 | 22 | 0 | [x] | 2,000 | psaSendMailForEffectiveBillRateUpdate |
| Order_Opportunity_MatchError_Reporting | 9.0 | 17 | 0 | [x] | 200 |
| CampaignTagsBatchable | 10.0 | * | 0 | [x] | 2,000 |	 
| CampaignTagsDeleteBatchable | 11.0 | * | 30 | [x] | 2,000 |
| OpportunityOwner_Batchable | 13.0 | * | 50 | [x] | 200 | 	 
| TrackingEventLog_CalculateSummary | 14.0 | * | 15 | [x] | 2,000 |	 	 
| NotifyCaseTeamMember | 15.0 | * | 0 | [x] | 2,000 |
| Opportunity_Split_Batchable	| 101.0 | * | 1/15 | [ ] | 25 |	 	 
| ProcessInstance_Batchable | 103.0 | * | 0/3 | [ ]	| 2,000 |	 	 
| Subscription_Batchable	| 106.0 | - | 4/7 | [ ] | 100 |
| AccountMergeBatchable | 107.0 | * | 1/3 | [ ] | 2,000 |	 	 
| DuplicateMigrateBatchable | 108.0 | *	| 1/3 | [ ]	| 2,000 | 	 
| RenewalPotentialBatchable | 109.0 | * | 0/2 | [ ] | 25 |	 	 
| DatedConversionRateBatchable | 110.0 | * | 55 | [x] | 100 |	 	 
| Integration_Batchable | 1,001.0 | * | 0/2 | [ ] | 1 |	 	 
| Lead_Batchable | 1,002.0 | * | 3/6 | [ ] | 500 |	 	 
| AccountReadOnly_Batchable | 1,004.0 | * | 3/6 | [ ] | 2,000	| 	 
| AccountHierarchy_Batchable | 1,005.0 | * | 1/3 | [ ] | 2,000 | 	 
| Order_Opportunity_Batchable	| 1,006.0	| *	| 2/5 | [ ]	| 1 |	 	 

## Best Practices
 

### Scheduling

When scheduling apex one needs to first examine what is on the system.   Some jobs benefit from running frequently, in that they accumulate more work over time so it is a small task to run every 5 minutes, but a huge task to run once a week.   As a general rule, you should not schedule a job so frequently that it cannot complete before its next scheduled time.   If you have a job that takes 15 minutes maximum, do not schedule to run less than once every 20 minutes.  If processing only needs to be done once a day, then schedule the job once a day.   Or twice if you are paranoid the job might miss it's normal run time.     If you schedule a job too frequently, there will be regular e-mail messages generated telling you the job is already running.  This message is intended to let you know when a job is stuck in processing excessively long.

When pushing new code for your job into production you will need to make sure the job is not scheduled to run while the push or test push is in progress.   This is easiest accomplished by editing the Hour__c field.

### Start Method

The start method is time critical.  If it takes your code too long to complete the execute method, your job will never run.  Also, only one start method on the system runs at a time, so if the start method takes to long other jobs will also be blocked from starting.   Inside the start method, standard governor limits apply.   So the goal of an execute method should be strictly to either return a Database.QueryLocator or List of objects to update with minimal processing.   If you can write a clever query to prune the number of records returned, that is great.   But you already have a list of records and need to do a for loop over the records to filter the record list, do that processing in the execute method.

Since standard governor limits apply inside a start method, sometimes queries need to be carefully structured to limit the number of records returned without hitting the governor limits.   For example suppose one wanted to make a Database.Batchable<SObject> implementation that could clone AccountTag objects to a custom AccountTag__c object.  A very bad way to do this would be: 

DON'T DO:

```
global Database.QueryLocator start(Database.BatchableContext bc) {

     Set<Id> excludeIds = new Set<Id>();

     for(AccountTag__c accountTag : [select TagId__c from AccountTag__c]) {

         excludeIds.add(accountTag.TagId__c);

     }

     Set<Id> accountTagIds = new Map<Id,Account_Tag>([select Id from Account_Tag]).keySet();

     return Database.getQueryLocator([select  ItemId,Name,TagDefinitionId,Type,SystemModstamp from AccountTag where Id not in :excludeIds]);

}
```
 
This type of code is likely to work well on a test sandbox.  But as soon as you move it to an environment with a full data set, you will find the first query hits a governor limit because there will be too many AccountTag__c objects on the system.   At first thought you might think you could fix this simply by putting in a limit on the query.  But then effectively your where condition is not filtering all the objects it should.   To solve this particular problem requires taking a step back and asking what is the goal.   If the goal is to create a new AccountTag__c object for each Account_Tag object, then one could simply limit the query by CreatedDate.   Chances are though, if we are cloning an object we are actually interested in capturing updates and deletes as well.   In that case we might do something like:

DO:

```
global DateTime currentRunTime;

global Database.QueryLocator start(Database.BatchableContext bc) {

     currentRunTime = DateTime.now();

     StringSetting__c lastRun = StringSetting__c.getInstance("LastRunAccountTag");

     final DateTime lastRunTime = DateTime.valueOf(lastRun);

     return Database.getQueryLocator([select  IsDeleted,ItemId,Name,TagDefinitionId,Type,SystemModstamp from AccountTag where SystemModstamp >= :lastRunTime ALL ROWS]);

}
```

In this case we solved the problem simply by adding a custom setting that storing the time last time we successfully ran in as string setting.  Presumably elsewhere finish method we would update the value of the custom setting.

Although we could not take advantage of an inner query in this scenario, sometimes that is an option as well.   For example lets say we want to create a record Foo__c for any opportunity that is more than 4 days old.   We could do the following: 

DO:

```
global Database.QueryLocator start(Database.BatchableContext bc) {

     final DateTime oldDate = Date.today().addDays(-4);

     return Database.getQueryLocator([select Id from Opportunity where CreatedDate <= :oldDate and Id not in (select OpportunityId__c from Foo__c)]);

}
```


One might why in this case we would do an inner query, but in the previous scenario we didn't.  Quite simply, there is no way to create a lookup field for a AccountTag Id value.  That means in the first example TagId__c was probably a text field.  Salesforce will not allow one to select an Id field from a text field. 

The final issue of interest about these methods is when return a List and when to return a Query Locator.   The general rule is only return a list if you are certain you won't hit the standard governor limit.  If there is any question about if a limit would be reached, then return a Query Locator.   However, in some cases it is meaningful to return a List and then set a limit explicitly to avoid the governor limits.  For example, if you were routing leads from the New Leads queue.   Routing leads is a slow process, so you probably never want to process more that a couple of thousands at a time.  Since a lead won't show-up again once routed, you can simply schedule the job regular to be certain every lead will eventually be routed from the queue.  If in doubt, use a Query Locator.

### Execute Method
 
The excute method is where you should be doing most of your processing.  The biggest don't is, do not do bulk updates without capturing errors.   The biggest DO is keep track of those errors so you can report the failures.

 

DON'T DO:

```
global void excute(Database.BatchableContext bc, List<Lead> leads) {
     try {
          update leads;
     }
     catch(Exception e) {
          System.debug(e);
     }
}
```

DO:

```
global List<String> errorList = new List<String>();

global void execute(Database.BatchableContext bc, List<Lead> leads) {

     for(Database.SaveResult sr : Database.update(leads,false) ) {

          Lead ld = leads.remove(0);

          if(! sr.isSuccess()) {

               errorList.add('Failed to update Lead.Id='+ld.Id+': '+sr.getErrors());

          }

     }

}
```

Of course for this code to work, you will need to have your class implement Database.Stateful.


### Finish Method
 
The finish method is where you should report your results.  Generally we only send an e-mail message if there were errors.   You should only send an e-mail on success if that is an explicit requirement, to avoid spamming those receiving the e-mail with un-interesting messages.



DON'T DO: 

```
global void finish(Database.BatchableContext bc) {
   for(AsyncApexJob j : [select Status, NumberOfErrors from AsyncApexJob where Id = :bc.getJobId()]) {
       Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

       ...
   }
}
```
 

while the code is efficently written, it fails if a null pointer is passed for bc.   Slightly more verbose code can avoid that problem: 

BETTER:

```
global void finish(Database.BatchableContext bc) {
     Id jobId = null;
     if(bc != null) {
          jobId = bc.getJobId();
     }

     AsyncApexJob job = new AsyncApexJob(Status='Job not found', NumberOfErrors=1);
     for(AsyncApexJob j : [select Status, NumberOfErrors from AsyncApexJob where Id = :jobId]) {
          job = j;
     }
     Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
     ...
}
```
 

This is probably good enough.  However, the perfectionist will note, we have two lines of code that never get tested if we pass a null value.  It is possible to refactor this code to get 100% test coverage.  Quite simply:

BEST:

```
global void finish(Database.BatchableContext bc) {
     finish([select Status, NumberOfErrors from AsyncApexJob where Id = :bc.getJobId()]);
}

global void finish(AsyncApexJob job) {
     Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
     ...
}
```
 

Notice like the original we are back to having our finish process throwing an exception when bc is null.   However, this is OK.  Because we know to expect this behaviour we can catch the exception when we call the first finish class from our test code.   Then we call the second test class with a dummy AsyncApexJob object we construct in our test class.   We now have very readable code, that can be covered 100% by testing with no need to do things like actually schedule the class to run in our test method.

### Test Class
 
General best practices for test method apply.  In most cases it is not neccessary to actually queue a job to test it.  Is is extremely rare to actually reference a Database.BatchableContext value in the execute method, but fairly common in the finish method.  Still, usually code can be written to accept a null value.  e.g. 

 

### HasWork Method
 
The hasWork method is called to check if your scheduled job needs to run at all.  Salesforce uses an extremely restriction on these queries.   It is probably best to explain with an actual example:

```
     global DateTime lastProcessedDateTime = DateTime.now().addDays(-3);

     global override Boolean hasWork() {
          DateTimeSetting__c lastProcessed = DateTimeSetting__c.getInstance(LAST_PROCESSED_KEY);
          if(lastProcessed != null && lastProcessed.Value__c != null) {
               lastProcessedDateTime = lastProcessed.Value__c;
          }
          return (0 < [ 
              select count() from Opportunity
              where SystemModstamp >= :lastProcessedDateTime
                  and IsOwnerLookupCurrent__c = false
              limit 1 ]);
     }
```

In this case really want to run whenever there is an opportunity with IsOwnerLookupCurrent__c is false.   However, if we attempt that query salesforce will complain there are way too many records to scan.   In order to avoid that limit we need to be able to add another criteria on something salesforce indexes such as SystemModstamp that will drop the list of records to search below 10,000 records.   In this case we decided to use a last processing time value we maintain in the rest of our code.
 
In theory, we would love to require the hasWork method for all scheduled jobs.   Unfortunately, not all scheduled jobs have criteria for what records to processed that can be written to run within the limits imposed by salesforce at this point of the processing.

### See Also

https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_scheduler.htm
