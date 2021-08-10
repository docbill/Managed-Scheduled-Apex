// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * Test class for ApexScheduleManager.  This class tests all the new advanced scheduling features we wrapped around ApexScheduler
 * with the ApexScheduleManager class.
 *
 * @version 2021-07-27
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2018-02-05 - Created
 * @since 2020-03-30 - US252351 - Ignore metadata scheduledTimeMap entries
 * @since 2020-12-04 - Removed ScheduledApex__c support
 * @since 2020-12-09 - Renamed from DailyScheduler2Test
 * @since 2021-07-27 - Removed references to Task_Owner__c field
 */
@isTest
public class ApexScheduleManagerTest {

    static final String DEFAULT_JOB_NAME = ApexScheduler.DEFAULT_JOB_NAME;

	static {
		ApexScheduleManager.testRecordPrefix = null;
        ApexScheduler.scheduledTimeMapUnfiltered.clear();
    }

    @isTest
	static void schedule() {
		Test.startTest();
		ApexScheduleManager.schedule(null,1,5,8,true);
		CronTrigger ct = [
			SELECT
				CronExpression
			FROM CronTrigger
			WHERE CronJobDetailId IN (
					select Id
					from CronJobDetail 
					where Name = :DEFAULT_JOB_NAME+' 00')
			ORDER BY CreatedDate DESC
			LIMIT 1 ];
		System.assertEquals('0 0 * * * ?',ct.CronExpression);
		ApexScheduleManager.schedule(null,1,5,8,true);
		CronTrigger ct2 = [
			SELECT
				CronExpression
			FROM CronTrigger
			WHERE CronJobDetailId IN (
					select Id
					from CronJobDetail 
					where Name = :DEFAULT_JOB_NAME+' 00')
			ORDER BY CreatedDate DESC
			LIMIT 1 ];
		System.assertEquals('0 0 * * * ?',ct2.CronExpression);
		Test.stopTest();
	}

	@isTest
	static void getEffectiveFrequencyTest() {
		List<ApexScheduleManager.CronTriggerCopy> cronTriggerList = new List<ApexScheduleManager.CronTriggerCopy>{
			new ApexScheduleManager.CronTriggerCopy(null,'0 5 * * * \\?','WAITING'),
			new ApexScheduleManager.CronTriggerCopy(null,'0 4 11 3 2 \\? 2018','DELETED'),
			new ApexScheduleManager.CronTriggerCopy(null,'0 3 11 3 2 \\? 2018','DELETED') };
		Test.startTest();
		System.assertEquals(1,new ApexScheduleManager(6,1,5,8).getEffectiveFrequency(cronTriggerList));
		System.assertEquals(2,new ApexScheduleManager(7,1,5,8).getEffectiveFrequency(cronTriggerList));
		System.assertEquals(3,new ApexScheduleManager(8,1,5,8).getEffectiveFrequency(cronTriggerList));
		Test.stopTest();
	}

	@isTest
	static void scheduleFutureTest() {
		ApexScheduleManager.settings.JobName__c = ApexScheduler.DEFAULT_JOB_NAME;
		upsert ApexScheduleManager.settings;
		ApexScheduleManager ds2  = new ApexScheduleManager(0,1,5,8);
		Test.startTest();
		System.assertEquals(
			DEFAULT_JOB_NAME+' 02,0 2 11 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 03,0 3 11 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 04,0 4 11 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 05,0 5 * * * ?\n'
				+DEFAULT_JOB_NAME+' 06,0 6 11 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 07,0 7 11 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 08,0 8 11 3 2 ? 2018',
			String.join(ds2.scheduleFuture(DateTime.newInstance(2018,02,03,11,0,0)),'\n'));
		ds2  = new ApexScheduleManager(57,1,5,8);
		System.assertEquals(
			DEFAULT_JOB_NAME+' 58,0 58 14 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 59,0 59 14 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 00,0 0 * * * ?\n'
				+DEFAULT_JOB_NAME+' 01,0 1 15 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 02,0 2 15 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 03,0 3 15 3 2 ? 2018\n'
				+DEFAULT_JOB_NAME+' 04,0 4 15 3 2 ? 2018',
			String.join(ds2.scheduleFuture(DateTime.newInstance(2018,02,03,14,56,30)),'\n'));
		ds2  = new ApexScheduleManager(36,2,6,4);
		System.assertEquals(
			DEFAULT_JOB_NAME+' 38,0 38 4 30 7 ? 2020\n'
				+DEFAULT_JOB_NAME+' 40,0 40 4 30 7 ? 2020\n'
				+DEFAULT_JOB_NAME+' 42,0 42 * * * ?\n'
				+DEFAULT_JOB_NAME+' 44,0 44 4 30 7 ? 2020',
			String.join(ds2.scheduleFuture(DateTime.newInstance(2020,07,30,4,36,59)),'\n'));
		Test.stopTest();
	}
	
	static ApexScheduler.ScheduledTime createScheduledTime(Boolean isActive,String name,String hour,String minute,Id userId,Decimal scope,Decimal priority,Boolean mustRun,String className) {
		return ApexSchedulerTest.createScheduledTime(isActive,name,hour,minute,userId,scope,priority,mustRun,className);
	}
	
	@isTest
	static void sortAsyncApexJobsTest() {
		List<ApexScheduler.ScheduledTime> stList = (new List<ApexScheduler.ScheduledTime>{
			createScheduledTime(true,'Batchable1',null,null,null,null,100.0,null,'Batchable1'),
			createScheduledTime(true,'Batchable2',null,null,null,null,76.0,null,null),
			createScheduledTime(true,'Batchable 4',null,null,null,null,86.0,null,'Batchable4'),
			createScheduledTime(true,'Batchable 6',null,null,null,null,99.0,null,'Batchable6'),
			createScheduledTime(true,'Batchable7',null,null,null,null,100.0,null,null)
		} );
		Map<String,ApexScheduler.ScheduledTime> stMap = new Map<String,ApexScheduler.ScheduledTime>();
		for(ApexScheduler.ScheduledTime st : stList) {
			stMap.put(st.name,st);
		}
		ApexScheduler.scheduledTimeMapUnfiltered = stMap;
		Map<String,Decimal> priorityMap = ApexScheduleManager.createPriorityMap(stMap.values());
		System.assertEquals(stList[0].priority,priorityMap.get(stList[0].className.toLowerCase()),'stList[0]='+stList[0]);
		System.assertEquals(stList[1].priority,priorityMap.get(stList[1].name.toLowerCase()),'stList[1]='+stList[1]);
		System.assertEquals(null,priorityMap.get(stList[2].name.toLowerCase()),'stList[2]='+stList[2]);
		System.assertEquals(stList[2].Priority,priorityMap.get(stList[2].className.toLowerCase()),'stList[2]='+stList[2]);
		System.assertEquals(null,priorityMap.get(stList[3].name.toLowerCase()),'stList[3]='+stList[3]);
		System.assertEquals(stList[3].priority,priorityMap.get(stList[3].className.toLowerCase()),'stList[3]='+stList[3]);
		System.assertEquals(stList[4].priority,priorityMap.get(stList[4].name.toLowerCase()),'stList[4]='+stList[4]);
		System.assertNotEquals(null,ApexScheduleManager.priorityMap);
		ApexScheduleManager.priorityMap = priorityMap;
		List<ApexScheduleManager.AsyncApexJobCopy> jobs = new List<ApexScheduleManager.AsyncApexJobCopy>{
			new ApexScheduleManager.AsyncApexJobCopy((Id)'7071800000qF4NM',null,'Batchable1'),
			new ApexScheduleManager.AsyncApexJobCopy((Id)'7071800000qF4JJ',null,'Batchable2'),
			new ApexScheduleManager.AsyncApexJobCopy((Id)'7071800000qF4JF',null,'Batchable3'),
			new ApexScheduleManager.AsyncApexJobCopy((Id)'7071800000qF4JH',null,'Batchable4') };
		List<ApexScheduleManager.AsyncApexJobCopy> sortedJobs = ApexScheduleManager.sortAsyncApexJobs(jobs);
		System.assertEquals(jobs.size(),sortedJobs.size());
		System.assertEquals(jobs[1],sortedJobs[0]);
		System.assertEquals(jobs[3],sortedJobs[1]);
		System.assertEquals(jobs[0],sortedJobs[2]);
		System.assertEquals(jobs[2],sortedJobs[3]);
		Test.startTest();
		// just for the sake of coverage
		ApexScheduleManager.prioritizeFlexQueue(sortedJobs);
		Test.stopTest();
	}

	@isTest
	static void executeCoverageTest() {
		ApexScheduleManager.settings.SortFlexQueue__c = true;
        ApexScheduleManager.settings.JobName__c = ApexScheduler.DEFAULT_JOB_NAME;
		// we'll call the execute method, but we are relying on the above tests to make sure the call works correctly.
		ApexScheduleManager ds2  = new ApexScheduleManager(0,1,5,8);
		Test.startTest();
		ds2.execute(null);
		Test.stopTest();
	}

	@isTest
	static void fixScheduledApexMetadataTest() {
		DateTime startTime = DateTime.now();
		ApexScheduleManager asm  = new ApexScheduleManager(0,1,5,8);
		Metadata.DeployContainer container = asm.fixScheduledApexMetadata(startTime);
		Map<String,ApexScheduleManager.ScheduledMedatataValues> smValuesMap = new Map<String,ApexScheduleManager.ScheduledMedatataValues>();
		for(Metadata.Metadata record : container.getMetadata()) {
			ApexScheduleManager.ScheduledMedatataValues smValues = new ApexScheduleManager.ScheduledMedatataValues((Metadata.CustomMetadata)record);
			smValuesMap.put(record.fullName,smValues);
			System.assertNotEquals(null,smValues.minute,'smValues.minute,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.hour,'smValues.hour,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.dayOfWeek,'smValues.dayOfWeek,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.dayOfMonth,'smValues.dayOfMonth,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.month,'smValues.month,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.year,'smValues.year,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.cronSchedule,'smValues.cronSchedule,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.isActive,'smValues.cronSchedule,record.fullName='+record.fullName);
			if(String.isNotBlank(smValues.jsonConstructor)) {
				System.assertNotEquals(null,smValues.jsonChecksum,'smValues.cronSchedule,record.fullName='+record.fullName);
			}
			System.assertNotEquals(null,smValues.taskOwnerId,'smValues.cronSchedule,record.fullName='+record.fullName);
			System.assertNotEquals(null,smValues.taskOwnerName,'smValues.cronSchedule,record.fullName='+record.fullName);
		}
		System.assertNotEquals(0,smValuesMap.size(),'smValuesMap.size()');
		ApexScheduleManager.ScheduledMedatataValues smValues1 = smValuesMap.get('Scheduled_Apex.TEST_ApexSchedulerTest');
		System.assertNotEquals(null,smValues1,'Scheduled_Apex.TEST_ApexSchedulerTest');
		System.assertEquals(true,smValues1.isActive,'Scheduled_Apex.TEST_ApexSchedulerTest.isActive');
		//System.assertEquals('{}',smValues1.jsonConstructor,'Scheduled_Apex.TEST_ApexSchedulerTest.jsonConstructor');
		System.assertEquals('mZFLkyvTelC5g8XnyQrpOw==',smValues1.jsonChecksum,'Scheduled_Apex.TEST_ApexSchedulerTest.jsonChecksum');
		ApexScheduleManager.ScheduledMedatataValues smValues2 = smValuesMap.get('Scheduled_Apex.TEST_ApexSchedulerTest2');
		System.assertNotEquals(null,smValues2,'Scheduled_Apex.TEST_ApexSchedulerTest2');
		System.assertEquals(true,smValues2.isActive,'Scheduled_Apex.TEST_ApexSchedulerTest2.isActive');
		//System.assertEquals(null,smValues2.jsonConstructor,'Scheduled_Apex.TEST_ApexSchedulerTest2.jsonConstructor');
		System.assertEquals(null,smValues2.jsonChecksum,'Scheduled_Apex.TEST_ApexSchedulerTest2.jsonChecksum');
	}
}