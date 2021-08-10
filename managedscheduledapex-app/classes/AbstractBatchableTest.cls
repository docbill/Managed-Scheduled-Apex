// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * This is the test class for AbstractBatchable.
 * 
 * @version 2020-04-14
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2014-04-21 created
 * @since 2020-01-15 Catch EmailException so we can run this test in sandboxes without mass email coverage
 * @since 2020-03-05 US248556 - Update to have AbstractBatchableBase tests
 * @since 2020-04-14 Test Fix - clone list in coverage test 
 */
@isTest
global class AbstractBatchableTest extends AbstractBatchable {
    /**
     * Default contstructor
     */
    global AbstractBatchableTest() {
        super('AbstractBatchableTest');
    }
    
    /**
     * start method
     */
    global Database.QueryLocator start(Database.BatchableContext bc) { 
        return Database.getQueryLocator([select Id from User limit 100]);
    }
    
    /**
     * dummy execute method
     */
    global void execute(Database.BatchableContext bc, List<SObject> records) {}
    
    public static Boolean hasWorkTest(AbstractBatchableBase batchable) {
        Boolean retval = batchable.hasWork();
        System.assertNotEquals(null,retval);
        return retval;
    }
    
    @IsTest
    static void startAndExecuteTest() {
        Test.startTest();
        List<SObject> records = startAndExecuteTest(new AbstractBatchableTest(),null);
        Test.stopTest();
        System.assert(! records.isEmpty());
    }
    
    public static List<Object> startAndExecuteTest(Database.Batchable<Object> batchable,Iterable<Object> recordsIterable,List<Object> retval) {
        Iterable<Object> result = batchable.start(null);
        if(recordsIterable != null) {
            System.assertNotEquals(null,result);
            result = recordsIterable;
        }
        if(result instanceof Database.QueryLocator){
            ApexPages.StandardSetController ssc = new ApexPages.StandardSetController((Database.QueryLocator)result);
            ssc.setPageSize(100);
            retval = ssc.getRecords();
        }
        else {
            if(retval == null) {
                retval = new List<Object>();
            }
            for(Iterator<Object> i = result.iterator();i.hasNext();) {
                retval.add( i.next() );
            }
        }
        if(batchable instanceof AbstractBatchableBase) {
            System.assertEquals(0,((AbstractBatchableBase)batchable).errorList.size(),((AbstractBatchableBase)batchable).errorList);
        }
        batchable.execute(null,retval);
        if(batchable instanceof AbstractBatchable) {
            System.assertEquals(0,((AbstractBatchableBase)batchable).errorList.size(),((AbstractBatchableBase)batchable).errorList);
        }
        return retval;
    }

    public static List<SObject> startAndExecuteTest(Database.Batchable<SObject> batchable,List<SObject> records) {
        return (List<SObject>)startAndExecuteTest((Database.Batchable<Object>)batchable,(Iterable<Object>)records,new List<SObject>());
    }
    
    public static void finishTest1(Database.Batchable<SObject> batchable) {
        finishTest1Base((Database.Batchable<Object>)batchable);
    }

    public static void finishTest1Base(Database.Batchable<Object> batchable) {
        batchable.finish((Database.BatchableContext)null);
    }
    
    @isTest
    static void finishTest2() {
        Test.startTest();
        finishTest2(new AbstractBatchableTest());
        Test.stopTest();
    }
    
    public static void finishTest2(AbstractBatchableBase batchable) {
        try {
            batchable.finish((AsyncApexJob)null);
        }
        catch(EmailException ex) {}
    }
    
    @isTest
    static void sendErrorsTest() {
        Test.startTest();
        sendErrorsTest(new AbstractBatchableTest());
        Test.stopTest();
    }
    
    public static void sendErrorsTest(AbstractBatchableBase batchable) {
        batchable.errorList.add('anything');
        try {
            System.assertNotEquals(null,batchable.sendErrors(null));
        }
        catch(EmailException ex) {}
    }
    
    @IsTest
    static void coverageTest() {
        Test.startTest();
        AbstractBatchableTest ab = new AbstractBatchableTest();
        coverageTest(ab,null);
        Test.stopTest();
    }

    @IsTest
    static void executeBatchTest() {
        Test.startTest();
        AbstractBatchableTest ab = new AbstractBatchableTest();
        ab.executeBatch(2000);
        Test.stopTest();
    }    

    /** 
     * Quick and dirty testing that will give a class coverage.  One can then implement 
     * implementation specific functional tests.
     */
    public static List<Object> coverageTest(Database.Batchable<Object> batchable,Iterable<Object> recordsIterable,List<Object> retval)
    {
        if(batchable instanceof AbstractBatchableBase) {
            hasWorkTest((AbstractBatchableBase)batchable);
        }
        retval = startAndExecuteTest(batchable,recordsIterable,retval);
        try {
            finishTest1Base((Database.Batchable<Object>)batchable);
        }
        catch(Exception ex) {}
        if(batchable instanceof AbstractBatchableBase) {
            try {
                finishTest2((AbstractBatchableBase)batchable);
            }
            catch(Exception ex) {}
        }
        if(batchable instanceof AbstractBatchableBase) {
            sendErrorsTest((AbstractBatchableBase)batchable);
        }
        return retval;
    }

    /** 
     * Quick and dirty testing that will give a class coverage.  One can then implement 
     * implementation specific functional tests.
     */
    public static void coverageTest(Database.Batchable<SObject> batchable,List<SObject> records) {        
        List<SObject> records2 = new List<SObject>();
        if(records != null) {
            records2 = records.clone();
            records2.clear();
        }
        coverageTest((Database.Batchable<Object>)batchable,(Iterable<Object>)records,records2);
    }
}