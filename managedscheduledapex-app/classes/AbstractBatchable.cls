// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is an abstract class to help reduce the efforts in implementing batchable classes. 
 * 
 * @version 2020-02-26
 * 
 * @author Bill Riemers <briemers@redhat.com>
 * @since 2014-04-01 Created
 * @since 2014-09-18 Removed implements stateful from the base class
 * @since 2014-09-19 Added lookupJob method
 * @since 2014-11-04 Add CreatedDate to the lookupJob query
 * @since 2020-02-26 US248556 - Code moved to AbstractBatchableBase, this class exists for backwards compatability
 */
global abstract class AbstractBatchable extends AbstractBatchableBase implements Database.Batchable<SObject> {
    /**
     * Constructor that assigns a name.
     */
    global AbstractBatchable(String batchName) {
        super( batchName );
    }

    /**
     * Method to execute this batch job.
     * @param scope the size of this job
     * @return jobId
     */    
    global override String executeBatch(Integer scope) {
        return Database.executeBatch(this,scope);
    }
}