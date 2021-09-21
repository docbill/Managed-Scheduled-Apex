// Copyright Red Hat
// SPDX-License-Identifier: GPL-3.0-only
/**
 * Test class for Opportunity_Split_Batchable
 *
 * @version 2018-09-13
 * 
 * @author Bill C Riemers <briemers@redhat.com>
 * @since 2018-09-13 - Created
 */
@isTest
private class Cleanup_BatchableTest {
	@testSetup
	static void testSetup() {
		List<Product2> productList = TestDataFactory_Product2.productList;
		System.assertNotEquals(0,productList.size());
		System.assertEquals(true,productList[0].IsActive);
		List<Product2> aptsProductList = TestDataFactory_Product2.aptsBaseProductList;
	}

	@isTest
	static void eligibleFieldTest() {
		Cleanup_Batchable cb = new Cleanup_Batchable();
		Test.startTest();
		System.assertNotEquals(null,cb.eligibleField);
		Test.stopTest();
	}

	@isTest
	static void fromObjectTest() {
		Cleanup_Batchable cb = new Cleanup_Batchable();
		cb.lastProcessedKey = 'Expiring_Product.Cleanup';
		Test.startTest();
		System.assertEquals('Expiring_Product__c',cb.fromObject);
		Test.stopTest();
	}

	@isTest
	static void startTest() {
		Map<Id,Product2> productMap = new Map<Id,Product2>(TestDataFactory_Product2.productList);
		productMap.putAll(new Map<Id,Product2>(TestDataFactory_Product2.aptsBaseProductList));
		Cleanup_Batchable cb = new Cleanup_Batchable();
		cb.criterias.addAll(new List<String>{
			'CreatedDate >= :HOURS_AGO_1',
			'LastModifiedDate <= :NOW',
			'SystemModStamp <= :NOW',
			'SystemModStamp >= :LAST_PROCESSED' } );
		cb.eligibleField = 'IsActive';
		cb.fromObject = 'Product2';
		cb.lastProcessedKey = 'Cleanup_Batchable.LastPrcoessedTest';

		Test.startTest();
		System.assert(cb.hasWork(),'Expected hasWork to report records to delete');
		cb.minFrequency = 24*7*36525; // 100 years
		System.assert(cb.hasWork(),'Expected hasWork to report records to delete');
		ApexPages.StandardSetController ssc = new ApexPages.StandardSetController(cb.start(null));
		ssc.setPageSize(100);
		List<Product2> products = ssc.getRecords();
		Test.stopTest();

		for(Product2 prod : products ) {
			Product2 prod2 = productMap.remove(prod.Id);
			System.assertNotEquals(null,prod2,'Unexpected product: '+[select Id, Name, CreatedDate, IsActive from Product2 where Id = :prod.Id]);
		}
		for(Product2 prod : productMap.values()) {
			System.assertEquals(false,prod.IsActive,'Expected to delete all active products');
		}
	}

	@isTest
	static void executeTest() {
		Map<Id,Product2> productMap = new Map<Id,Product2>(TestDataFactory_Product2.productList);

		Cleanup_Batchable cb = new Cleanup_Batchable();
		cb.eligibleField = 'IsActive';
		cb.lastProcessedKey = 'Cleanup_Batchable.LastPrcoessedTest';

		Test.startTest();
		cb.execute(null,productMap.values());
		Test.stopTest();

		for(Product2 p : [select Id,IsActive from Product2 where Id in :productMap.keySet()]) {
			Product2 p2 = productMap.get(p.Id);
			System.assertEquals(p2.IsActive,p.IsActive);
			if(p2.IsActive) {
				System.assertEquals(null,p2,'Expected product to be deleted');
			}
		}
	}

	@IsTest
	static void coverageTest() {
		Map<Id,Product2> productMap = new Map<Id,Product2>(TestDataFactory_Product2.productList);
		productMap.putAll(new Map<Id,Product2>(TestDataFactory_Product2.aptsBaseProductList));
		Cleanup_Batchable cb = new Cleanup_Batchable();
		cb.criterias = new List<String>{
			'CreatedDate >= :HOURS_AGO_1',
			'LastModifiedDate <= :NOW',
			'SystemModStamp <= :NOW',
			'SystemModStamp >= :LAST_PROCESSED',
			'IsActive = true' };
		cb.eligibleField = 'IsActive';
		cb.fromObject = 'Product2';
		cb.lastProcessedKey = 'Cleanup_Batchable.LastPrcoessedTest';
		Test.startTest();
		AbstractBatchableTest.coverageTest(cb,productMap.values());
		Test.stopTest();
	}
}