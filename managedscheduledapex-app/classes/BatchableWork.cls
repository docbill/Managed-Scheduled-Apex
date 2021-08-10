// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is an interface to check if a batch job should be scheduled.
 * 
 * @version 2020-04-02
 * 
 * @author Bill Riemers <briemers@redhat.com>
 * @since 2020-04-02 US248556 - Created
 */
public interface BatchableWork {
    /**
     * Check if there is work for this job to do.  The purpose of this method is to allow the trigger
     * invoked by the daily scheduler to tell the daily scheduler if this job can be skipped.
     * 
     * @return false if there is no work to do.
     */
    Boolean hasWork();

    /**
     * Method to execute this batch job.
     * @param scope the size of this job
     * @return jobId
     */    
    String executeBatch(Integer scope);
}