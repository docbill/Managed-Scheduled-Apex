// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is a generic class for deleting obsolete records.  This is intended to be use with a json contructor that assigns the soql string.   With great power, comes great
 * responsability.  As something like { soql: 'select Id from Opportunity'; } would proceed to delete every single opportunity in the system!   As a saftey feature, this class
 * will only delete objects with a field named:  Cleanup_Eligible__c, and that field must return a true value.
 *  
 * In addition to the literals defined https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_select_dateformats.htm it there are some
 * other constant values defined.  These include: 
 * :LAST_PROCESSED, :NOW, :HOURS_AGO_1, :HOURS_AGO_2, ..., :HOURS_AGO_23
 * 
 * If the Cleanup_Eligible__c field contains all the selection criteria, a minimum json constructor would be:
 *    { 
 *       "lastProcessedKey: "APTS_SKU_Staging.LastProcessed", 
 *     }
 * 
 * An example that specifies the time range, and explicitly assigns the from object would be:
 *    { 
 *       "lastProcessedKey: "APTS_SKU_Staging.LastProcessed", 
 *       "fromObject" : "APTS_SKU_Staging__c",
 *       "criterias" : [ "SystemModStamp >= :LAST_PROCESSED", "systemModStamp < :LAST_N_MONTHS:3","Status__c != 'New'" ]
 *     }
 * 
 * For debugging, it might be usef specify a query instead:
 *    { 
 *       "lastProcessedKey": "APTS_SKU_Staging.LastProcessed", 
 *       "soql": "select Id from APTS_Sku_Staging__c where SystemModStamp >= :LAST_PROCESSED and SystemModStamp < LAST_N_MONTHS:3 and Status__c != 'New' and Cleanup_Eligible__c = true" 
 *     }
 * 
 * @version 2018-09-11
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2018-09-11 - Created
 */
global class Cleanup_Batchable extends AbstractBatchable {
	/**
	 * How often in hours should we run this even with no work?
	 */
	global static final Integer MIN_FREQUENCY = 3 * 24;
	/**
	 * The default elilible Field
	 */
	global static final String ELIGIBLE_FIELD = 'Cleanup_Eligible__c';

	/**
	 * Cleanup Eligible Field.
	 * 
	 */
	global String eligibleField {
		get {
			if(eligibleField == null) {
				eligibleField = ELIGIBLE_FIELD;
			}
			return eligibleField;
		}
		set;
	}

	/** 
	 * Name of a custom setting key for last processed datetime. Assigning this will also auto assign systemModStampMin.   Although not required, this value is strongly advinced.
	 * the normal naming convention would be <fromObject>.Cleanup.   If you have multiply jobs for the same object append something unique to this. 
	 */
	global String lastProcessedKey = null;

	/** Name of the object to query.  Normally this will be assigned from the leading part of the lastProcessedKey with __c appended.   */
	global String fromObject {
		get {
			if(String.isBlank(fromObject) && ! String.isBlank(lastProcessedKey)) {
				fromObject = lastProcessedKey.split('[.]',2)[0]+'__c';
			}
			return fromObject;
		}
		set;
	}

	/**
	 * How often in hours should we run this even with no work?
	 */
	global Integer minFrequency {
		get {
			if(minFrequency == null) {
				minFrequency = MIN_FREQUENCY;
			}
			return minFrequency;
		}
		set;
	}

	/** Dynamic query */
	global String soql {
		get {
			if(soql == null && ! String.isBlank(fromObject) ) {
				// always have an eligible field criteria unless the feature 
				// has been disabled by assigning a blank value to eligibleField
				List<String> criterias = this.criterias.clone();
				String eligibleField = this.eligibleField;
				if(! String.isBlank(eligibleField)) {
					for(String c : criterias) {
						if(c.trim().startsWithIgnoreCase(eligibleField)) {
							eligibleField = null;
							break;
						}
					}
					if(eligibleField != null) {
						criterias.add(eligibleField +' = true');
					}
				}
				soql = 'SELECT Id FROM '+fromObject+' WHERE '+String.join(criterias,' AND ');
			}
			return soql;
		}
		set;
	}

	/** Dynamic query conditions */
	global List<String> criterias {
		get {
			if(criterias == null ) {
				criterias = new List<String>();
			}
			return criterias;
		}
		set;
	}


	/** 
	 * Keep track of the lastProcessedDateTime
	 */
	global DateTimeSetting__c lastProcessed {
		get {
			if(lastProcessed == null) {
				if(lastProcessedKey != null) {
					lastProcessed = DateTimeSetting__c.getInstance(lastProcessedKey);
				}
				if(lastProcessed == null || lastProcessed.Value__c == null) {
					lastProcessed = new DateTimeSetting__c(Name=lastProcessedKey,Value__c=DateTime.newInstance(2000,1,1));
				}
			}
			return lastProcessed;
		}
		set;
	}

	/**
	 * Default constructor.
	 */
	global Cleanup_Batchable() {
		super(null);
	}

	/**
	 * Check if there is work for this job to do.
	 *
	 * @return false if there is no work to do.
	 */
	global override Boolean hasWork() {
		final DateTime NOW = DateTime.now();
		final DateTime HOURS_AGO_1 = NOW.addHours(-1);
		final DateTime HOURS_AGO_2 = NOW.addHours(-2);
		final DateTime HOURS_AGO_3 = NOW.addHours(-3);
		final DateTime HOURS_AGO_4 = NOW.addHours(-4);
		final DateTime HOURS_AGO_5 = NOW.addHours(-5);
		final DateTime HOURS_AGO_6 = NOW.addHours(-6);
		final DateTime HOURS_AGO_7 = NOW.addHours(-7);
		final DateTime HOURS_AGO_8 = NOW.addHours(-8);
		final DateTime HOURS_AGO_9 = NOW.addHours(-9);
		final DateTime HOURS_AGO_10 = NOW.addHours(-10);
		final DateTime HOURS_AGO_11 = NOW.addHours(-11);
		final DateTime HOURS_AGO_12 = NOW.addHours(-12);
		final DateTime HOURS_AGO_13 = NOW.addHours(-13);
		final DateTime HOURS_AGO_14 = NOW.addHours(-14);
		final DateTime HOURS_AGO_15 = NOW.addHours(-15);
		final DateTime HOURS_AGO_16 = NOW.addHours(-16);
		final DateTime HOURS_AGO_17 = NOW.addHours(-17);
		final DateTime HOURS_AGO_18 = NOW.addHours(-18);
		final DateTime HOURS_AGO_19 = NOW.addHours(-19);
		final DateTime HOURS_AGO_20 = NOW.addHours(-20);
		final DateTime HOURS_AGO_21 = NOW.addHours(-21);
		final DateTime HOURS_AGO_22 = NOW.addHours(-22);
		final DateTime HOURS_AGO_23 = NOW.addHours(-23);
		final DateTime LAST_PROCESSED = lastProcessed.Value__c;
		Boolean retval = ((! String.isBlank(lastProcessed.Name)) && NOW.addHours(-minFrequency) > lastProcessed.Value__c);
		if(! retval) {
			System.debug('Query: '+soql);
			for(SObject o : Database.query(soql+' limit 1')) {
				retval = true;
			}
		}
		return retval;
	}

	/**
	 * Start method impl for Database.Batchable interface.  A fairly small
	 * scope value will need to be used for the current implementation.
	 * 
	 * @param   bc batchable contents
	 * @return  list of ready records
	 */
	global Database.QueryLocator start(Database.BatchableContext bc) {
		final DateTime NOW = DateTime.now();
		final DateTime HOURS_AGO_1 = NOW.addHours(-1);
		final DateTime HOURS_AGO_2 = NOW.addHours(-2);
		final DateTime HOURS_AGO_3 = NOW.addHours(-3);
		final DateTime HOURS_AGO_4 = NOW.addHours(-4);
		final DateTime HOURS_AGO_5 = NOW.addHours(-5);
		final DateTime HOURS_AGO_6 = NOW.addHours(-6);
		final DateTime HOURS_AGO_7 = NOW.addHours(-7);
		final DateTime HOURS_AGO_8 = NOW.addHours(-8);
		final DateTime HOURS_AGO_9 = NOW.addHours(-9);
		final DateTime HOURS_AGO_10 = NOW.addHours(-10);
		final DateTime HOURS_AGO_11 = NOW.addHours(-11);
		final DateTime HOURS_AGO_12 = NOW.addHours(-12);
		final DateTime HOURS_AGO_13 = NOW.addHours(-13);
		final DateTime HOURS_AGO_14 = NOW.addHours(-14);
		final DateTime HOURS_AGO_15 = NOW.addHours(-15);
		final DateTime HOURS_AGO_16 = NOW.addHours(-16);
		final DateTime HOURS_AGO_17 = NOW.addHours(-17);
		final DateTime HOURS_AGO_18 = NOW.addHours(-18);
		final DateTime HOURS_AGO_19 = NOW.addHours(-19);
		final DateTime HOURS_AGO_20 = NOW.addHours(-20);
		final DateTime HOURS_AGO_21 = NOW.addHours(-21);
		final DateTime HOURS_AGO_22 = NOW.addHours(-22);
		final DateTime HOURS_AGO_23 = NOW.addHours(-23);
		final DateTime LAST_PROCESSED = lastProcessed.Value__c;
		System.debug('Query: '+soql);
		if(! hasWork()) {
			finish(bc);
		}
		return Database.getQueryLocator(soql);
	}

	/**
	 * execute method impl for Database.Batchable interface
	 *
	 * @param 	bc batchable content
	 * @param 	objectList to delete
	 */
	global void execute(
		Database.BatchableContext bc, 
		List<SObject> objectList)
	{
		if(! String.isBlank(eligibleField)) {
			final Set<Id> keys = new Map<Id,SObject>(objectList).keySet();
			// this is a saftey feature.  We won't delete any object that is not marked as eligible
			String query = 'select Id from '+objectList[0].getSObjectType().getDescribe().getName()+' where '+eligibleField+' = true and Id in :keys';
			System.debug(query);
			objectList = Database.query(query);
		}
		for(Database.DeleteResult r : Database.delete(objectList,false)) {
			SObject o = objectList.remove(0);
			for(Database.Error e : r.getErrors()) {
				errorList.add('Failed to delete '+o+': '+e);
			}
		}
		// executeNoEmail( oppHeardeStagingList );
		// email any errors that resulted in an uncaught exception
		if(! errorList.isEmpty()) {
			super.finish(lookupJob(bc));
		}
	}

	/**
	 * finish method
	 *
	 * @param job the async apex job
	 */
	global override void finish(AsyncApexJob job) {
		try {
			if(lastProcessedKey != null && errorList.isEmpty()) {
				DateTime lastProcessedDateTime = DateTime.now().addMinutes(-5);
				if(job != null && job.CreatedDate != null) {
					lastProcessedDateTime = job.CreatedDate;
				}
				if(lastProcessed.Value__c < lastProcessedDateTime) {
					lastProcessed.Value__c = lastProcessedDateTime;
					upsert lastProcessed;
				}
			}
		}
		catch(Exception e) {
			errorList.add('Failed to update lastProcessed '+e+'\n'+e.getStackTraceString());
		}
		super.finish(job);
	}

}