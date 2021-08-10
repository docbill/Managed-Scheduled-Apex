// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * ApexScheduleManager
 * 
 * This is a wrapper to the ApexScheduler class designed to enhance functionality.
 * After removing existing scheduled instances, execute the following commands 
 * within system log or anonymously schedule this job. This 
 * schedules the job to run every 1 minute with a fixed scheduled time every 5 minutes..
 *
 * 		ApexScheduleManager.schedule(null,1,5,8,false);
 *
 * Our suggested schedule is for your master job manager is:
 * 
 * 		ApexScheduleManager.schedule(null,2,6,4,true);
 * 
 * The suggested schedule for the average admin user is:
 * 		
 * 		ApexScheduleManager.schedule('ApexScheduler '+UserInfo.getUserEmail(),5,60,1,false);
 *
 * @version 2022-07-27
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2018-02-02 - Created this wrapper class
 * @since 2020-03-12 US248556 - Updated comments to list correct scheduling parameters.
 * @since 2020-04-01 US252351 - Used ApexScheduler.ScheduledTime instead of ScheduledApex__c
 * @since 2020-09-09 - Use Scheduled_Apex_Setting__c for configuration values
 * @since 2020-12-08 - Support fixing metadata
 * @since 2020-12-09 - renamed from DailyScheduler2
 * @since 2020-12-09 - Added support for jobname
 * @since 2021-04-26 US292725 - only update metadata when there is no deployment in progress
 * @since 2021-07-27 - Removed references to Task_Owner__c field
 */
global class ApexScheduleManager implements Schedulable {
    @TestVisible
    private static String testRecordPrefix = 'TEST.';

	@TestVisible
	final Integer start;
	@TestVisible
	Integer frequency;
	@TestVisible
	Integer modulus;
	@TestVisible
	Integer queueAhead;

	@TestVisible
	private static final Scheduled_Apex_Settings__c settings {
		get { return ApexScheduler.settings; }
	}

	/**
	 * Constructor which includes scheduling information.  If the custom setting are set, either null or those values must be used.
	 *
	 * @param start how many minute past the hour in which this job has been scheduled to start
	 * @param frequency how many minutes until the next time the job runs
	 * @param modulus how many minutes until a fixed slot (this should probably be a multiple of frequency)
	 * @param queueAhead how many slots should we have prescheduled in the immediate future
	 */
	global ApexScheduleManager(Integer start,Integer frequency,Integer modulus,Integer queueAhead) {
		this.start = start;
		this.frequency = frequency;
		this.modulus = modulus;
		this.queueAhead = queueAhead;
	}

	/**
	 * If the value is not null, update the custom setting, otherwise return the custom setting value.
	 * @param field name in the settingObject
	 * @param value the value to assign to this setting
	 * @return the updated value
	 */
	@TestVisible
	static Integer updateSetting(SObjectField field,Integer value) {
		Decimal dvalue = (Decimal)settings.get(field);
		if(value != null && (dvalue == null || value != dvalue.intValue())) {
			dvalue = value;
			settings.put(field,dvalue);
		}
		return dvalue.intValue();
	}

	/**
	 * If the value is not null, update the custom setting, otherwise return the custom setting value.
	 * @param field name in the settingObject
	 * @param value the value to assign to this setting
	 * @return the updated value
	 */
	@TestVisible
	static Object updateSetting(SObjectField field,Object value) {
		Object ovalue = settings.get(field);
		if(value != null && (ovalue == null || ! ovalue.equals(value))) {
			ovalue = value;
			settings.put(field,ovalue);
		}
		return ovalue;
	}

	/**
	 * Convience function to schedule the this class and set the custom settings.
	 * @param frequency haw many minutes until the next job runs
	 * @param modulus how many minutes until a fixed slot (this should probably be a multiple of frequency)
	 * @param queueAhead how many slots should we have prescheduled in the immediate future
	 */
	global static void schedule(String jobName,Integer frequency,Integer modulus,Integer queueAhead,Boolean sortFlexQueue) {
		frequency = updateSetting(Scheduled_Apex_Settings__c.Frequency__c,frequency);
		modulus = updateSetting(Scheduled_Apex_Settings__c.Modulus__c,modulus);
		queueAhead = updateSetting(Scheduled_Apex_Settings__c.QueueAhead__c,queueAhead);
		jobName = settings.JobName__c = blankValue(jobName,blankValue(settings.JobName__c,ApexScheduler.DEFAULT_JOB_NAME));
		sortFlexQueue = (Boolean)updateSetting(Scheduled_Apex_Settings__c.SortFlexQueue__c,sortFlexQueue);

		// validate settings
		System.assert(frequency >= 1 && frequency <= 60,'Frequency out of range');
		System.assert(modulus >= frequency && modulus <= 60,'Modulus out of range');
		System.assertEquals(modulus-Math.mod(modulus,frequency),modulus,'Modulus must be a multiple of frequency');
		System.assert(queueAhead > 0 && queueAhead <= 60,'Queue Ahead out of range');

		upsert settings;

		final String jobNamePrefix = jobName+' ';
		// abort existing jobs in a WAITING status
		for(CronTrigger ct : [
			SELECT Id
			FROM CronTrigger
			WHERE CronJobDetailId IN (
					select Id
					from CronJobDetail 
					where Name like :(jobNamePrefix+'%')) ] )
		{
			System.abortJob(ct.Id);
		}

		// queue new fixed jobs
		for(Integer start=0;start < 60;start+=frequency) {
			if(Math.mod(start,modulus) == 0) {
				String name = jobNamePrefix+(String.valueOf(start+100).substring(1));
				System.schedule(name, '0 '+start+' * * * ?', new ApexScheduleManager(start,frequency,modulus,queueAhead));
			}
		}
		
		// queue new jobs for the immediate future
		DateTime n = DateTime.now();
		new ApexScheduleManager(n.minute(),frequency,modulus,queueAhead).scheduleFuture(n);
	}

	/**
	 * Convience function to schedule the this class.
	 * @param current the value of DateTime.now()
	 * @return a list of what was scheduled for unit testing
	 */
	@TestVisible
	List<String> scheduleFuture(DateTime current) {
		List<String> scheduleList = new List<String>();
		// allow more than 1 minute to make sure the schedule start times really are in the future.
		DateTime minSchedule = current.addMinutes(1);
		// we need to align the next time with times that are multiples of the frequency
		DateTime next =  DateTime.newInstance(current.year(),current.month(),current.day(),current.hour(),current.minute(),0)
			.addMinutes(frequency-Math.mod(current.minute(),frequency));
		final String jobNamePrefix = settings.jobName__c+' ';
		for( Integer i=queueAhead; i-- > 0; next = next.addMinutes(frequency) ) 
		{
			if(next > minSchedule) {
				Integer nextStart = next.minute();
				String name = jobNamePrefix+String.valueOf(nextStart+100).substring(1);
				String ce = '0 '+nextStart+' * * * ?'; // use a fixed slot for repeated calls
				if(Math.mod(nextStart,modulus) != 0) {
					ce = '0 '+next.format('m H d M \'?\' yyyy'); // use a one time slot
				}
				try {
					scheduleList.add(name+','+ce);
					// most or all of these are probably already scheduled
					System.schedule(name,ce,new ApexScheduleManager(nextStart,frequency,modulus,queueAhead));
				}
				catch(Exception ex) {}
			}
		}
		return scheduleList;
	}

	/**
	 * call the getTriggerId method and catch any exception.
	 * @return triggerId or null
	 */
	global static Id getTriggerId(SchedulableContext sc) {
		try {
			return sc.getTriggerId();
		}
		catch(Exception ex) {}
		return null;
	}

	/**
	 * Find the effective frequency.   Written to accept either CronTrigger or CronTriggerCopy as the input, is it makes unit testing much easier.
	 * @param cronTriggerList either a list of CronTrigger or CronTriggerCopy values
	 * @return the discovered effective frequency
	 */
	@TestVisible
	Integer getEffectiveFrequency( List<Object> cronTriggerList )
	{
		Integer effectiveFrequency = null;
		for(Object obj : cronTriggerList ) {
			CronTriggerCopy ctw = getCronTriggerCopy( obj );
			try {
				Integer prevStart = Integer.valueOf((''+ctw.cronExpression).split(' ')[1]);
				if(prevStart != start) {
					if(effectiveFrequency == null) {
						effectiveFrequency = Math.mod(60+start-Math.mod(prevStart,60),60);
					}
					if(ctw.state == 'DELETED' || (ctw.state == 'WAITING' && Math.mod(prevStart,modulus) != 0)) {
						System.abortJob(ctw.id);
					}
				}
			}
			catch(Exception ex) {}
		}
		if(effectiveFrequency == null) {
			effectiveFrequency = frequency;
		}
		return effectiveFrequency;
	}

	/**
	 * execute method impl for Schedulable interface
	 *
	 */
	global void execute( SchedulableContext sc ) {
		// override values using custom settings (if available)
		frequency = settings.Frequency__c.intValue();
		if(frequency < 1) {
			frequency = 1;
		}
		else if(frequency > 60) {
			frequency = 60;
		}
		modulus = settings.Modulus__c.intValue();
		if(modulus < frequency) {
			modulus = frequency;
		}
		modulus -= Math.mod(modulus,frequency);
		queueAhead = settings.QueueAhead__c.intValue();
		if(queueAhead > 60) {
			queueAhead = 60;
		}
		final Id triggerId = getTriggerId(sc);
		final String jobNamePrefix = settings.jobName__c+' ';
		Integer effectiveFrequency = getEffectiveFrequency( [
			SELECT Id,
				CronExpression,
				State
			FROM CronTrigger
			WHERE CronJobDetailId IN (
					select Id
					from CronJobDetail 
					where Name like :(jobNamePrefix+'%'))
//				AND State != 'WAITING'
				AND PreviousFireTime != null
				AND Id != :triggerId
				ORDER BY PreviousFireTime DESC NULLS LAST 
				LIMIT 100 ] );

		ApexScheduler ds = new ApexScheduler(start,effectiveFrequency);

		ds.execute(sc);

		DateTime startTime = DateTime.now();
		scheduleFuture(startTime);

		if ( Scheduled_Apex_Settings__c.getInstance().SortFlexQueue__c != false ) {
			prioritizeFlexQueue(sortAsyncApexJobs([
				SELECT Id, ApexClass.Name, ApexClass.NamespacePrefix
				FROM AsyncApexJob 
				WHERE Status = 'Holding' 
					AND ApexClassId != null 
				ORDER BY CreatedDate, Id ]) );
		}
		// we do this last so we won't use up any queries needed for has work method calls
		if(settings.JobName__c == ApexScheduler.DEFAULT_JOB_NAME && Limits.getLimitQueries() > Limits.getQueries()) {
			fixScheduledApexMetadata(startTime);
		}
	}

	/** 
	 * We use a class rather than the sobject directly so we don't have issues with read only fields in our test class.
	 */
	@TestVisible
	static CronTriggerCopy getCronTriggerCopy(Object obj) {
		CronTriggerCopy retval;
		try {
			retval = new CronTriggerCopy(
				((CronTrigger)obj).Id,
				((CronTrigger)obj).CronExpression,
				((CronTrigger)obj).State );
		}
		catch(Exception ex) {
			retval = (CronTriggerCopy)obj;
		}
		return retval;
	}

	/** 
	 * We use a class rather than the sobject directly so we don't have issues with read only fields in our test class.
	 */
	@TestVisible
	static AsyncApexJobCopy getAsyncApexJobCopy(Object obj) {
		AsyncApexJobCopy retval;
		try {
			retval = new AsyncApexJobCopy(
				((AsyncApexJob)obj).Id,
				((AsyncApexJob)obj).ApexClass.NamespacePrefix,
				((AsyncApexJob)obj).ApexClass.Name );
		}
		catch(Exception ex) {
			retval = (AsyncApexJobCopy)obj;
		}
		return retval;
	}

	/** 
	 * This is a creates map of priority based on class name.
	 * @param scheduledTimeList
	 * @return map of priority based on class name
	 */
	@TestVisible
	static Map<String,Decimal> createPriorityMap(List<ApexScheduler.ScheduledTime> scheduledTimeList) {
		Map<String,Decimal> xpriorityMap = new Map<String,Decimal>();
		for(ApexScheduler.ScheduledTime sa : scheduledTimeList) {
			if(sa.priority != null) {
				String className = sa.className;
				if(className == null) {
					className = sa.Name;
				}
				if(className != null) {
					if(sa.namespacePrefix != null) {
						className = sa.namespacePrefix + '.' + className;
					}
					String classNameLC = className.toLowerCase();
					Decimal priority = xpriorityMap.get(classNameLC);
					if(priority == null || priority > sa.priority) {
						xpriorityMap.put(classNameLC,sa.priority);
					}
				}
			}
		}
		return xpriorityMap;
	}

	/** 
	 * This is a map of priority based on class name.
	 */
	@TestVisible
	static Map<String,Decimal> priorityMap {
		get {
			if(priorityMap == null) {
				priorityMap = createPriorityMap(ApexScheduler.scheduledTimeMapUnfiltered.values());
			} 
			return priorityMap;
		}
		set;
	}

	/**
	 * Called to sort jobs in the flex queue to the same order in the list.
	 * @param list of jobs to order
	 */
	@TestVisible
	static void prioritizeFlexQueue(List<AsyncApexJobCopy> asyncApexJobCopyList) {
		Id priorId = null;
		//System.debug(String.join(asyncApexJobCopyList,'\n'));
		for(AsyncApexJobCopy job : asyncApexJobCopyList) {
			//System.debug('Sorting Job: '+job.Id
			//	+','+job.apexClassNamespacePrefix+'.'+job.apexClassName
			//	+',position='+job.position
			//	+',priority='+job.priority);
			if(priorId != null) {
				try {
					//System.debug('try: moveAfterJob('+job.Id+','+priorId+')');
					Boolean result=FlexQueue.moveAfterJob(job.Id,priorId);
					//System.debug('moveAfterJob('+job.Id+','+priorId+')='+result);
					priorId = job.Id;
				}
				catch(Exception ex) {
					System.debug(ex);
					priorId = null;
				}
			}
			if(priorId == null) {
				try {
					//System.debug('try: moveJobToFront('+job.Id+')');
					Boolean result=FlexQueue.moveJobToFront(job.Id);
					//System.debug('moveJobToFront('+job.Id+')='+result);
					priorId = job.Id;
				}
				catch(Exception ex) {
					System.debug(ex);
				}
			}
		}
	}

	/**
	 * Sort scheduled apex in the order of priority, with any job without a priority dropped from  the list.
	 * @param asyncApexJobList holding jobs in a random order.
	 * @return sort in priority order
	 */
	@TestVisible
	static List<AsyncApexJobCopy> sortAsyncApexJobs(List<Object> asyncApexJobList) {
		List<AsyncApexJobCopy> jobs = new List<AsyncApexJobCopy>();
		for(Object obj : asyncApexJobList ) {
			jobs.add(getAsyncApexJobCopy(obj));
		}
		jobs.sort();
		return jobs;
	}

	/**
	 * This is a copy of CronTrigger, as we can't directly populate CronTrigger fields even in our test classes.
	 */
	public class CronTriggerCopy {
		public final Id id;
		public final String cronExpression;
		public String state;

		/**
		 * Constructor
		 * @param id CronTrigger.Id
		 * @param cronExpression CronTrigger.CronExpression
		 * @param state CronTrigger.State
		 */
		public CronTriggerCopy(Id id,String cronExpression, String state) {
			this.id = id;
			this.cronExpression = cronExpression;
			this.state = state;
		}
	}

	@TestVisible
	static Integer nextPosition = 0;

	/**
	 * This is a copy of CronTrigger, as we can't directly populate CronTrigger fields even in our test classes.
	 */
	public class AsyncApexJobCopy  implements Comparable {
		public final Id id;
		public final String apexClassNamespacePrefix;
		public final String apexClassName;
		public final Integer position;
		public final Decimal priority;

		/**
		 * Constructor
		 * @param id AsyncApexJob.Id
		 * @param createdDate for fifo sorting of equal priority jobs
		 * @param namespacePrefix AsyncApexJob.ApexClass.NamespacePrefix
		 * @param className AsyncApexJob.ApexClass.Name
		 */
		@TestVisible 
		AsyncApexJobCopy(Id id,String namespacePrefix,String className) {
			this.id = id;
			this.apexClassNamespacePrefix = namespacePrefix;
			this.apexClassName = className;
			this.position = nextPosition++;
			if(namespacePrefix != null) {
				className = namespacePrefix+'.'+className;
			}
			this.priority = priorityMap.get(className.toLowerCase());
		}

		/**
		 * Sorts in priority order with nulls last.
		 * @param compareTo
		 * @return -1, 0, or 1 for less than, equal to, or greater than respectively
		 */
		public Integer compareTo(Object compareTo) {
			Integer retval = -1;
			if(compareTo instanceOf AsyncApexJobCopy) {
				final AsyncApexJobCopy that = (AsyncApexJobCopy)compareTo;
				if(this.priority == that.priority) {
					if(this.position > that.position) {
						retval = 1;
					}
					else if(this.position == that.position) {
						retval = 0;
					}
				}
				else if(this.priority == null || (that.priority != null && this.priority > that.priority)) {
					retval = 1;
				}
			}
			return retval;
		}
	}

	global Metadata.DeployContainer fixScheduledApexMetadata(DateTime startTime) {
		List<Scheduled_Apex__mdt> scheduledApexList = ApexScheduler.scheduledApexMetadataList;
		Set<String> userIds = (new Set<String>{UserInfo.getUserId()});
		for(Scheduled_Apex__mdt sa : scheduledApexList) {
			if(testRecordPrefix == null || ! sa.MasterLabel.startsWith(testRecordPrefix)) {
				userIds.add(sa.Task_OwnerId__c);
			}
		}
		Map<String,Id> userIdMap = new Map<String,Id>();
		for(String userId : userIds) {
			try {
				userIdMap.put(userId,(Id)userId);
			}
			catch(Exception ex) {}
		}
		userIdMap.remove(null);
		Map<Id,User> userMap = getUserMap(userIdMap.values());
		Metadata.DeployContainer  container = null;
		if(userMap != null && ! userMap.isEmpty()) { 
			Map<String,Id> taskOwnerMap = new Map<String,Id>();
			Map<String,String> jsonContructorMap = new Map<String,String>();
			for(Scheduled_Apex__mdt sa : scheduledApexList) {
				if(testRecordPrefix == null || ! sa.MasterLabel.startsWith(testRecordPrefix)) {
					User taskOwner = userMap.get(userIdMap.get(sa.Task_OwnerId__c));
					if(taskOwner == null) {
						taskOwner = userMap.get(UserInfo.getUserId());
					}
					if( taskOwner != null ) {
						String minute = ApexScheduler.rangeString(sa.Minute__c,'-');
						String hour = ApexScheduler.rangeString(sa.Hour__c,'-');
						String dayOfMonth = ApexScheduler.rangeString(sa.DayOfMonth__c,'*');
						String month = ApexScheduler.rangeString(sa.Month__c,'*');
						String dayOfWeek = ApexScheduler.rangeString(sa.DayOfWeek__c,'?');
						String year = ApexScheduler.rangeString(sa.Year__c,'*');
						String cronSchedule = (
							minute+' '
							+hour+' '
							+dayOfMonth+' '
							+month+' '
							+dayOfWeek+' '
							+year
						).abbreviate(80);
						Boolean isActive = (
							(sa.Active__c == true) 
							&& minute != '-' 
							&& hour != '-' 
							&& dayOfMonth != '-'
							&& month != '-'
							&& year != '-'
						);
						if( sa.Active__c != isActive
							|| sa.Minute__c != minute
							|| sa.Hour__c != hour
							|| sa.DayOfMonth__c != dayOfMonth 
							|| sa.Month__c != month
							|| sa.DayOfWeek__c != dayOfWeek
							|| sa.Year__c != year
							|| sa.CronSchedule__c != cronSchedule
							|| sa.Task_OwnerId__c != (String)taskOwner.Id
							|| sa.Task_Owner_Name__c != userName(taskOwner)
							|| (isActive && sa.JSON_Checksum__c != checksumValue(sa.JSON_Constructor__c))
						) {
							String fullName = 'Scheduled_Apex.'+sa.QualifiedApiName; 
							taskOwnerMap.put(fullName,taskOwner.Id);
							jsonContructorMap.put(fullName,sa.JSON_Constructor__c);
						}
					}
				}
			}
			if(! taskOwnerMap.isEmpty()) {
				container = fixScheduledApexMetadata(startTime,taskOwnerMap,jsonContructorMap);
			}
		}
		return container;
	}

	static Metadata.DeployContainer fixScheduledApexMetadata(DateTime startTime,Map<String,Id> taskOwnerMap,Map<String,String> jsonConstructorMap) {
		Metadata.DeployContainer container = null;
		Map<Id,User> userMap = getUserMap(taskOwnerMap.values());
		if(userMap != null) {
			List<Metadata.Metadata> records = Metadata.Operations.retrieve(
				Metadata.MetadataType.CustomMetadata,
				new List<String>(taskOwnerMap.keySet())
			);
			System.assertNotEquals(0,records.size(),'taskOwnerMap.keySet()='+taskOwnerMap.keySet());
			container = new Metadata.DeployContainer();
			List<String> recordFullNames = new List<String>();
			for(Metadata.Metadata record : records) {
				recordFullNames.add(record.fullName);
				User owner = userMap.get(taskOwnerMap.get(record.fullName));
				System.assertNotEquals(null,owner,'record.fullName='+record.fullName);
				if(owner != null) {
					ScheduledMedatataValues values = new ScheduledMedatataValues((Metadata.CustomMetadata)record);
					values.addMetadata(container,jsonConstructorMap,owner);
				}
			}
			try {
				if(! (settings.DisableCompile__c || isDeploymentInProgress())) {
					Metadata.Operations.enqueueDeployment(container, null);
				}
			}
			catch(Exception ex) {
				System.debug('This is expected in a test class: '+ex);
				if(! System.isFuture() && ! System.isBatch()) {
					fixScheduledApexMetadataFuture(startTime,taskOwnerMap,jsonConstructorMap);
				}
			}
		}
		return container;
	}

	@future(Callout=true)
	static void fixScheduledApexMetadataFuture(DateTime startTime,Map<String,Id> taskOwnerMap,Map<String,String> jsonConstructorMap) {
		fixScheduledApexMetadata(startTime,taskOwnerMap,jsonConstructorMap);
	}

	static String userName(User u) {
		List<String> nameList = new List<String>();
		if(String.isNotBlank(u.FirstName)) {
			nameList.add(u.FirstName);
		}
		if(String.isNotBlank(u.LastName)) {
			nameList.add(u.LastName);
		}
		return String.join(nameList,' ');
	}

	static String checksumValue(String value) {
		String retval = null;
		if(String.isNotBlank(value)) {
			Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(value));
			if(hash != null) {
				retval = EncodingUtil.base64Encode(hash).abbreviate(255);
			}
		}
		return retval;
	}

	static Map<Id,User> getUserMap(List<Id> userIds) {
		Map<Id,User> retval = null;
		if( Limits.getLimitQueryRows() >= Limits.getQueryRows()+userIds.size()) {
			retval = new Map<Id,User>([
				select
					FirstName,
					LastName,
					Id
				from User
				where Id in :userIds and IsActive = true
			]);
		}
		return retval;
	}

	static Object replaceNull(Object value,Object defaultValue) {
		if(value == null) {
			value = defaultValue;
		}
		return value;
	}

	static String blankValue(String value,String defaultValue) {
		if(String.isBlank(value)) {
			value = defaultValue;
		}
		return value;
	}

	enum METADATA_FIELD { 
		ACTIVE_FIELD,
		CRON_SCHEDULE_FIELD,
		DAY_OF_WEEK_FIELD,
		DAY_OF_MONTH_FIELD,
		JSON_CHECKSUM_FIELD,
		MINUTE_FIELD,
		HOUR_FIELD,
		MONTH_FIELD,
		TASK_OWNER_ID_FIELD,
		TASK_OWNER_NAME_FIELD,
		YEAR_FIELD
	}

	static final Map<String,METADATA_FIELD> METADATA_FIELD_MAP {
		get {
			if(METADATA_FIELD_MAP == null) {
				METADATA_FIELD_MAP = (new Map<String,METADATA_FIELD>{
					Scheduled_Apex__mdt.Active__c.getDescribe().getName() => METADATA_FIELD.ACTIVE_FIELD,
					Scheduled_Apex__mdt.CronSchedule__c.getDescribe().getName() => METADATA_FIELD.CRON_SCHEDULE_FIELD,
					Scheduled_Apex__mdt.DayOfWeek__c.getDescribe().getName() => METADATA_FIELD.DAY_OF_WEEK_FIELD,
					Scheduled_Apex__mdt.DayOfMonth__c.getDescribe().getName() => METADATA_FIELD.DAY_OF_MONTH_FIELD,
					Scheduled_Apex__mdt.JSON_Checksum__c.getDescribe().getName() => METADATA_FIELD.JSON_CHECKSUM_FIELD,
					Scheduled_Apex__mdt.Minute__c.getDescribe().getName() => METADATA_FIELD.MINUTE_FIELD,
					Scheduled_Apex__mdt.Hour__c.getDescribe().getName() => METADATA_FIELD.HOUR_FIELD,
					Scheduled_Apex__mdt.Month__c.getDescribe().getName() => METADATA_FIELD.MONTH_FIELD,
					Scheduled_Apex__mdt.Task_OwnerId__c.getDescribe().getName() => METADATA_FIELD.TASK_OWNER_ID_FIELD,
					Scheduled_Apex__mdt.Task_Owner_Name__c.getDescribe().getName() => METADATA_FIELD.TASK_OWNER_NAME_FIELD,
					Scheduled_Apex__mdt.Year__c.getDescribe().getName() => METADATA_FIELD.YEAR_FIELD
				});
			}
			return METADATA_FIELD_MAP;
		}
		set;
	}

	static void assignTo(ScheduledMedatataValues source,Metadata.CustomMetadataValue saValue)
	{
		switch on METADATA_FIELD_MAP.get(saValue.field) {
			when ACTIVE_FIELD {
				saValue.value = source.isActive;
			}
			when CRON_SCHEDULE_FIELD {
				saValue.value = source.cronSchedule;
			}
			when DAY_OF_WEEK_FIELD {
				saValue.value = source.dayOfWeek;
			}
			when DAY_OF_MONTH_FIELD {
				saValue.value = source.dayOfMonth;
			}
			when JSON_CHECKSUM_FIELD {
				saValue.value = source.jsonChecksum;
			}
//				when JSON_CONSTRUCTOR_FIELD {
//					saValue.value = source.jsonConstructor;
//				}
			when MINUTE_FIELD {
				saValue.value = source.minute;
			}
			when HOUR_FIELD {
				saValue.value = source.hour;
			}
			when MONTH_FIELD {
				saValue.value = source.month;
			}
			when TASK_OWNER_ID_FIELD {
				saValue.value = source.taskOwnerId;
			}
			when TASK_OWNER_NAME_FIELD {
				saValue.value = source.taskOwnerName;
			}
			when YEAR_FIELD {
				saValue.value = source.year;
			}
			when else {
				System.debug('Ignored field: '+saValue.field+'='+saValue.value);
			}
		}
	}

	static void assignTo(Metadata.CustomMetadataValue saValue,ScheduledMedatataValues target)
	{
		switch on METADATA_FIELD_MAP.get(saValue.field) {
			when ACTIVE_FIELD {
				target.isActive = (Boolean)saValue.value;
			}
			when CRON_SCHEDULE_FIELD {
				target.cronSchedule = (String)saValue.value;
			}
			when DAY_OF_WEEK_FIELD {
				target.dayOfWeek = (String)saValue.value;
			}
			when DAY_OF_MONTH_FIELD {
				target.dayOfMonth = (String)saValue.value;
			}
			when JSON_CHECKSUM_FIELD {
				target.jsonChecksum = (String)saValue.value;
			}
//			when JSON_CONSTRUCTOR_FIELD {
//				target.jsonConstructor = (String)saValue.value
//			}
			when MINUTE_FIELD {
				target.minute = (String)saValue.value;
			}
			when HOUR_FIELD {
				target.hour = (String)saValue.value;
			}
			when MONTH_FIELD {
				target.month = (String)saValue.value;
			}
			when TASK_OWNER_ID_FIELD {
				target.taskOwnerId = (String)saValue.value;
			}
			when TASK_OWNER_NAME_FIELD {
				target.taskOwnerName = (String)saValue.value;
			}
			when YEAR_FIELD {
				target.year = (String)saValue.value;
			}
			when else {
				System.debug('Ignored field: '+saValue.field+'='+saValue.value);
			}
		}
	}

	@TestVisible
	class ScheduledMedatataValues {
		public final Metadata.CustomMetadata record;
		public String minute;
		public String hour;
		public String dayOfWeek;
		public String dayOfMonth;
		public String month;
		public String year;
		public String cronSchedule;
		public Boolean isActive;
		public String jsonConstructor;
		public String jsonChecksum;
		public String taskOwnerId;
		public String taskOwnerName;

		@TestVisible
		public ScheduledMedatataValues(final Metadata.CustomMetadata record) {
			this.record = record;
			for (Metadata.CustomMetadataValue saValue : record.values) {
				assignTo(saValue,this);
			}
		}

		void addMetadata(Metadata.DeployContainer container,Map<String,String> jsonConstructorMap, User owner) {
			minute = ApexScheduler.rangeString(minute,'-');
			hour = ApexScheduler.rangeString(hour,'-');
			dayOfWeek = ApexScheduler.rangeString(dayOfWeek,'?');
			dayOfMonth = ApexScheduler.rangeString(dayOfMonth,'*');
			month = ApexScheduler.rangeString(month,'*');
			year = ApexScheduler.rangeString(year,'*');
			cronSchedule = ( 
				minute+' '
				+ hour+' '
				+ dayOfMonth+' '
				+ month+' '
				+ dayOfWeek+' '
				+ year ).abbreviate(80);
			isActive = (((Boolean)replaceNull(isActive,false))
				&& minute != '-'
				&& hour != '-'
				&& dayOfWeek != '-'
				&& month != '-'
				&& dayOfMonth != '-'
				&& year != '-' );
			System.debug('fullname='+record.fullName);
			jsonConstructor = jsonConstructorMap.get(record.fullName);
			jsonChecksum = checksumValue(jsonConstructor);
			if(isActive && String.isNotBlank(jsonChecksum)) {
				try {
					JSON.deserializeUntyped(jsonConstructor);
				}
				catch(Exception ex) {
					jsonChecksum = (''+ex).left(255).trim();
					isActive = false;
				}
			}
			taskOwnerId = (String)owner.Id;
			taskOwnerName = userName(owner);

			for(Metadata.CustomMetadataValue saValue : record.values) {
				assignTo(this,saValue);
			}
			container.addMetadata(record);
		}
	}

	private static Boolean isDeploymentInProgress() {
		String endPoint = URL.getSalesforceBaseUrl().toExternalForm() 
		+ '/services/data/v51.0/tooling/query?q=SELECT%20Id%2C%20Status%2C%20StartDate%2C%20CompletedDate%20FROM%20DeployRequest%20WHERE%20not%20Status%20like%20%27%25ed%25%27';
		HTTPRequest req = new HTTPRequest();
		req.setEndpoint(endPoint);
		req.setMethod('GET');
		req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
		req.setHeader('Content-Type','application/json; charset=UTF-8');
		req.setHeader('Accept','application/json');
		Http h = new Http();
		HttpResponse res = h.send(req);
		Boolean retval = true;
		// Response to a get should be 200
		if (res.getStatusCode() == 200) {
			Map<String,Object> results = (Map<String,Object>)JSON.deserializeUntyped(res.getBody());
			retval = (0 != results.get('size'));
		}
		return retval;
	}
}