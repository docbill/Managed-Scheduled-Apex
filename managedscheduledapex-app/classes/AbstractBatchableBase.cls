// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is an abstract class to help reduce the efforts in implementing batchable classes. 
 * 
 * @version 2020-03-04
 * 
 * @author Bill Riemers <briemers@redhat.com>
 * @since 2020-02-26 Created from AbstractBatchable
 * @since 2020-02-26 US248556 - Renamed to AbstractBatchableBase and no longer marked as implements Database.Batchable<SObject>
 * @since 2020-03-04 US248556 - Added executeBatch method to allow customizing how the class is queued in the ApexScheduler
 * @since 2020-04-02 US248556 - Implement nameable interface
 */
global abstract class AbstractBatchableBase implements Nameable, BatchableWork {
    
    /**
     * Set the batchname.   Part of the nameable interface.
     * 
     * @param batchName
     */
    global void setName(String batchName) {
        this.batchName = batchName;
    }
    
    /**
     * Get the batchname.   Part of the nameable interface.
     * 
     * @return batchName
     */
    global String getName() {
        return batchName;
    }
    
    /** The name of this batch job. */
    global String batchName {
        get {
            if(batchName == null) {
                batchName = (''+this).split(':',2)[0];
            }
            return batchName;
        }
        set;
    }

    /** Keep track of any errors. */
    global List<String> errorList {
        get {
            if(errorList == null) {
                errorList = new List<String>();
            }
            return errorList;
        }
        set;
    }

    /**
     * Constructor that assigns a name.
     */
    global AbstractBatchableBase(String batchName) {
        this.batchName = batchName;
    }

    /**
     * Method to execute this batch job.
     * @param scope the size of this job
     * @return jobId
     */    
    global abstract String executeBatch(Integer scope);

    /**
     * Check if there is work for this job to do.  The purpose of this method is to allow the trigger
     * invoked by the daily scheduler to tell the daily scheduler if this job can be skipped.
     * 
     * This is part of the BatchableWork interface.
     * 
     * @return false if there is no work to do.
     */
    global virtual Boolean hasWork() { return true; }

    /**
     * Called to find the AsyncApexJob
     */
    global AsyncApexJob lookupJob(Database.BatchableContext bc) {
        AsyncApexJob job = null;
        try {
            job = [
                SELECT
                    Status,
                    NumberOfErrors,
                    JobItemsProcessed,
                    TotalJobItems,
                    CreatedBy.Email,
                    CreatedDate
                FROM AsyncApexJob 
                WHERE Id = :bc.getJobId() ];
        }
        catch(Exception ignored) {}
        return job;
    }

    /**
     * The finish method impl for Database.Batchable interface.  If your interface is stateless (default), then
     * you will want call this from execute() to email errors.
     *
     * @param bc database context
     */
    global virtual void finish(Database.BatchableContext bc) {
        System.debug('Finish called');
        finish(lookupJob(bc));
    }


    /**
     * finish method
     *
     * @param job the async apex job
     */
    global virtual void finish(AsyncApexJob job) {
        sendErrors(job);
    }

    /**
     * Called to send error message by e-mail.   *
     * @param job the async apex job
     * @return the message which was sent
     */
    global virtual Messaging.SingleEmailMessage sendErrors(AsyncApexJob job) {
        Messaging.SingleEmailMessage mail = null;
        // Send an email to notify us of the jobs status
        if((job != null && job.NumberOfErrors != null && job.NumberOfErrors > 0) || ! errorList.isEmpty()) {
            if(job == null) {
                job = new AsyncApexJob();
            }
            String totalJobItems = String.valueOf(job.TotalJobItems);
            if(job.TotalJobItems == null) {
                totalJobItems = 'at least one';
            }
            String numberOfErrors = String.valueOf(job.NumberOfErrors);
            if(job.NumberOfErrors == null) {
                numberOfErrors = String.valueOf(errorList.size());
            }
            mail = new Messaging.SingleEmailMessage();
            String[] toAddresses = new String[] { 'sf-error-list@redhat.com' };
            mail.setToAddresses( toAddresses );
            mail.setSubject( batchName+' failures ' + job.Status +' run as '+UserInfo.getUserName() );
            String body = 'The batch Apex job processed ' + totalJobItems + ' batches with ' + numberOfErrors + ' failures.\n';
            for(String e : errorList) {
                body += e+'\n';
            }
            errorList.clear();
            mail.setPlainTextBody( body );
            Messaging.sendEmail( new Messaging.SingleEmailMessage[] { mail } );
        }
        return mail;
    }
}