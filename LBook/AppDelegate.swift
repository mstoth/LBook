//
//  AppDelegate.swift
//  LBook
//
//  Created by Michael Toth on 3/25/19.
//  Copyright © 2019 Michael Toth. All rights reserved.
//

import Cocoa
import CloudKit
import CoreData
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let container = CKContainer.default()

    var createdCustomZone = false
    var subscribedToPrivateChanges = false
    var subscribedToSharedChanges = false
    var privateDB:CKDatabase? = nil
    var sharedDB:CKDatabase? = nil
    var context:NSManagedObjectContext? = nil
    var zoneID:CKRecordZone.ID? = nil
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        // FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.virtualpianist.LBook")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert], completionHandler: {(granted,err) in
            if granted {
                print("authorization granted")
            } else {
                print("authorization not granted")
                // remind the server not to send notifications
            }
            if let err = err {
                print(err.localizedDescription)
            }
        })

        NotificationCenter.default.addObserver(self, selector: #selector(self.contextObjectsDidChange), name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: self.persistentContainer.viewContext)
            

        setup()
        NSApplication.shared.registerForRemoteNotifications()

        

//        let req = NSFetchRequest<Student>(entityName: "Student")
//        req.predicate = NSPredicate(value:true)
//        do {
//            let results = try context?.fetch(req)
//            for r in results! {
//                self.persistentContainer.viewContext.delete(r)
//            }
//        } catch {
//            print(error)
//        }
//
//        do {
//            try self.persistentContainer.viewContext.save()
//        } catch {
//            print(error)
//        }

//        let student = Student(context: persistentContainer.viewContext)
//        student.firstName = "Michael"
//        student.lastName = "Toth"
//
//        do {
//            try self.persistentContainer.viewContext.save()
//        } catch {
//            print(error)
//        }


    }

    func setup() {
        NSApp.registerForRemoteNotifications()

        self.privateDB = container.privateCloudDatabase
        self.sharedDB = container.sharedCloudDatabase
        context = persistentContainer.viewContext
        
        // Use a consistent zone ID across the user's devices
        // CKCurrentUserDefaultName specifies the current user's ID when creating a zone ID
        zoneID = CKRecordZone.ID(zoneName: "LessonBook", ownerName: CKCurrentUserDefaultName)
        
        // Store these to disk so that they persist across launches
        
        let privateSubscriptionId = "private-changes"
        let sharedSubscriptionId = "shared-changes"

        let createZoneGroup = DispatchGroup()
        if !self.createdCustomZone {
            createZoneGroup.enter()
            let customZone = CKRecordZone(zoneID: zoneID!)
            let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [customZone], recordZoneIDsToDelete: [] )
            createZoneOperation.modifyRecordZonesCompletionBlock = { (saved, deleted, error) in
                if (error == nil) {
                    self.createdCustomZone = true
                    let zone = saved?.first
                    self.zoneID=zone?.zoneID
                    
                    print("Created Custom Zone.")
                } else {
                    print(error?.localizedDescription ?? "nil")
                }
                // else custom error handling
                createZoneGroup.leave()
            }
            createZoneOperation.qualityOfService = .userInitiated
            self.privateDB?.add(createZoneOperation)
        }
        
        if !self.subscribedToPrivateChanges {
            let subscription = CKDatabaseSubscription(subscriptionID: privateSubscriptionId)
            let notification = CKSubscription.NotificationInfo()
            notification.shouldSendContentAvailable = true
            subscription.notificationInfo = notification
            
            let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
            operation.modifySubscriptionsCompletionBlock = { (sub,id,err) in
                if err != nil {
                    print(err)
                } else {
                    self.subscribedToPrivateChanges = true
                }
            }
            
//            let createSubscriptionOperation = self.createDatabaseSubscriptionOperation(subscriptionId: privateSubscriptionId)
//            createSubscriptionOperation.modifySubscriptionsCompletionBlock = { (subscriptions, deletedIds, error) in
//                if error == nil {
//                    print("Created Subscription.")
//                    self.subscribedToPrivateChanges = true
//                } else {
//                    print(error?.localizedDescription as Any)
//                }
//            }
            self.privateDB?.add(operation)
        }
        
        if !self.subscribedToSharedChanges {
            let createSubscriptionOperation = self.createDatabaseSubscriptionOperation(subscriptionId: sharedSubscriptionId)
            createSubscriptionOperation.modifySubscriptionsCompletionBlock = { (subscriptions, deletedIds, error) in
                if error == nil {
                    self.subscribedToSharedChanges = true
                    print("Subscribed to shared changes.")
                } else {
                    print(error?.localizedDescription ?? "nil")
                }
                // else custom error handling
            }
            self.sharedDB?.add(createSubscriptionOperation)
        }
        
        // Fetch any changes from the server that happened while the app wasn't running
        createZoneGroup.notify(queue: DispatchQueue.global()) {
            if self.createdCustomZone {
                self.fetchChanges(in: .private) {}
            }
        }
    }
    
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("In didRegisterForRemoteNotificationsWithDeviceToken")
    }
    
    @objc func contextObjectsDidChange(_ notification:NSNotification) {
        print("in contextObjectsDidChange")
        guard let userInfo = notification.userInfo else { return }
        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<Student>, inserts.count > 0 {
            print("Inserting")
            for i in inserts {
                let studentRecordID = CKRecord.ID(recordName: UUID().uuidString, zoneID:zoneID!)
                
                let studentRecord = CKRecord(recordType: "Student", recordID: studentRecordID)
                // we have created a new cloud record, save the recordID in the local Student record for future reference
                do {
                    i.recordName = studentRecordID.recordName
                    i.recordID = try NSKeyedArchiver.archivedData(withRootObject: studentRecordID, requiringSecureCoding: false)
                    // we don't want to trigger another contextObjectsDidChange in the middle of this
                    // turn off notification and turn it back on after saving
                    NotificationCenter.default.removeObserver(self, name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: self.context)
                    do {
                        try self.context?.save()
                    } catch {
                        print(error)
                    }
                    NotificationCenter.default.addObserver(self, selector: #selector(self.contextObjectsDidChange), name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: self.context)

                } catch {
                    print(error)
                }
                studentRecord["firstName"]=i.firstName
                studentRecord["lastName"]=i.lastName
                studentRecord["phone"]=i.phone
                self.privateDB?.save(studentRecord, completionHandler: {(rec,err) in
                    if let err = err {
                        print(err)
                    } else {
                        print("Saved Student to Cloud")
                    }
                })
            }
        }
        if let updates = userInfo[NSUpdatedObjectsKey] as? Set<Student>, updates.count > 0 {
            print("Updating")
            for u in updates {
                do {
                    let rid = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(u.recordID!) as! CKRecord.ID
                    privateDB?.fetch(withRecordID: rid, completionHandler: {(rec,err) in
                        if let err = err {
                            print(err)
                        } else {
                            rec?["firstName"]=u.firstName
                            rec?["lastName"]=u.lastName
                            rec?["phone"]=u.phone
                            self.privateDB?.save(rec!, completionHandler: {(rec,err) in
                                if let err = err {
                                    print(err)
                                } else {
                                    print("Updated Record on Cloud")
                                }
                            })

                        }
                    })
                } catch {
                    print(error)
                }
            }
        }
        if let deletes = userInfo[NSDeletedObjectsKey] as? Set<Student>, deletes.count > 0 {
            print("Deleting")
            for d in deletes {
                let rid = d.recordID
                if (rid == nil) {
                    break
                }
                do {
                    let recordID = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(rid!) as! CKRecord.ID
                    self.privateDB?.delete(withRecordID: recordID, completionHandler: {(rid,err) in
                        if let err = err {
                            print(err)
                        } else {
                            print("Deleted Record from Cloud")
                            do {
                                try self.context?.save()
                            } catch {
                                print(error)
                            }
                        }
                    })
                } catch {
                    print(error)
                }
            }
        }

    }

    
    func createDatabaseSubscriptionOperation(subscriptionId: String) -> CKModifySubscriptionsOperation {
        
        let subscription = CKDatabaseSubscription.init(subscriptionID: subscriptionId)
        let notificationInfo = CKSubscription.NotificationInfo()
        
        // send a silent notification
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        operation.qualityOfService = .utility
        return operation
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "LessonBookX")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
        })
        return container
    }()

    
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        print("Received notification!")
        // let viewController = NSApplication.shared.mainWindow?.contentView
        let dict = userInfo as! [String: NSObject]
        guard let notification:CKDatabaseNotification = CKNotification(fromRemoteNotificationDictionary:dict) as? CKDatabaseNotification else { return }
        NotificationCenter.default.removeObserver(self, name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: self.persistentContainer.viewContext)
        fetchChanges(in: notification.databaseScope) {
            NotificationCenter.default.addObserver(self, selector: #selector(self.contextObjectsDidChange), name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: self.persistentContainer.viewContext)
        }
    }
    
    
    // MARK: -- Remote Activity
    
    func fetchChanges(in databaseScope: CKDatabase.Scope, completion: @escaping () -> Void) {
        
        switch databaseScope {
        case .private:
            fetchDatabaseChanges(database: self.privateDB!, databaseTokenKey: "private", completion: completion)
        case .shared:
            fetchDatabaseChanges(database: self.sharedDB!, databaseTokenKey: "shared", completion: completion)
        case .public:
            fatalError()
        }
    }
    
    
    
    func fetchDatabaseChanges(database: CKDatabase, databaseTokenKey: String, completion: @escaping () -> Void) {
        
        var changedZoneIDs: [CKRecordZone.ID] = []
        
        var previousToken:CKServerChangeToken?
        let changeTokenData = UserDefaults.standard.value(forKey: "LessonBookDatabaseChangeToken") as? Data // Read change token from disk
        if (changeTokenData != nil) {
            do {
                previousToken = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(changeTokenData!) as? CKServerChangeToken
            } catch {
                previousToken = nil
            }
        }

        let changeToken:CKServerChangeToken? = previousToken
        
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: changeToken)
        operation.recordZoneWithIDChangedBlock = { (zoneID) in
            changedZoneIDs.append(zoneID)
        }
        operation.recordZoneWithIDWasDeletedBlock = { (zoneID) in
            // Write this zone deletion to memory
        }
        operation.changeTokenUpdatedBlock = { (token) in
            
            // Flush zone deletions for this database to disk
            let tokenData = try! NSKeyedArchiver.archivedData(withRootObject: token as Any, requiringSecureCoding: true)
            UserDefaults.standard.set(tokenData, forKey: "LessonBookDatabaseChangeToken")

            // Write this new database change token to memory
            
        }
        operation.fetchDatabaseChangesCompletionBlock = { (token, moreComing, error) in
            
            if let error = error {
                print("Error during fetch shared database changes operation", error)
                completion()
                return
            }
            
            // Flush zone deletions for this database to disk
            
            // Write this new database change token to memory
            let tokenData = try! NSKeyedArchiver.archivedData(withRootObject: token as Any, requiringSecureCoding: true)
            UserDefaults.standard.set(tokenData, forKey: "LessonBookDatabaseChangeToken")
            let zoneID = CKRecordZone.ID(zoneName: "LessonBook", ownerName: CKCurrentUserDefaultName)

            
            self.fetchZoneChanges(database: database, databaseTokenKey: databaseTokenKey, zoneIDs: [zoneID]) {
                // Flush in-memory database change token to disk
                let tokenData = try! NSKeyedArchiver.archivedData(withRootObject: token as Any, requiringSecureCoding: true)
                UserDefaults.standard.set(tokenData, forKey: "LessonBookDatabaseChangeToken")

                completion()
            }
        }
        operation.qualityOfService = .userInitiated
        if (databaseTokenKey == "private") {
            self.privateDB?.add(operation)
        }
        if (databaseTokenKey == "shared") {
            self.sharedDB?.add(operation)
        }
    }

    func fetchAllZoneChanges() {
        
    }
    func fetchZoneChanges(database: CKDatabase, databaseTokenKey: String, zoneIDs: [CKRecordZone.ID], completion: @escaping () -> Void) {
        // Look up the previous change token for each zone
        
        var previousToken:CKServerChangeToken?
        let changeTokenData = UserDefaults.standard.value(forKey: "LessonBookZoneChangeToken") as? Data // Read change token from disk
        if (changeTokenData != nil) {
            do {
                previousToken = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(changeTokenData!) as? CKServerChangeToken
            } catch {
                previousToken = nil
            }
        }

        var optionsByRecordZoneID = [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration]()
        
        for zoneID in zoneIDs {
            let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            options.previousServerChangeToken = previousToken
            optionsByRecordZoneID[zoneID] = options
        }
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: optionsByRecordZoneID)
        
        operation.recordChangedBlock = { (record) in
            print("Record changed:", record)
            // Write this record change to memory
            print("Record Name: ",record.recordID.recordName)
            let req = NSFetchRequest<Student>(entityName: record.recordType)
            let pred = NSPredicate(format: "recordName == %@", record.recordID.recordName)
            req.predicate = pred
            do {
                let student = try self.context?.fetch(req).first
                student?.firstName = record["firstName"]
                student?.lastName = record["lastName"]
                student?.phone = record["phone"]
            } catch {
                print(error)
            }
            
        }
        operation.recordWithIDWasDeletedBlock  = { (rid,rtype) in
            print("Record deleted.")
            print(rid)
        }
        operation.recordZoneChangeTokensUpdatedBlock = { (zoneId, token, data) in
            // Flush record changes and deletions for this zone to disk
            // Write this new zone change token to disk
            let tokenData = try! NSKeyedArchiver.archivedData(withRootObject: token as Any, requiringSecureCoding: true)
            UserDefaults.standard.set(tokenData, forKey: "LessonBookZoneChangeToken")

        }
        operation.recordZoneFetchCompletionBlock = { (zoneId, changeToken, _, _, error) in
            if let error = error {
                print("Error fetching zone changes for \(databaseTokenKey) database:", error)
                print("Resetting token.")
                UserDefaults.standard.set(nil, forKey: "LessonBookZoneChangeToken")
                DispatchQueue.main.async {
                    self.fetchChanges(in: (self.privateDB?.databaseScope)!, completion: {
                        completion()
                    })
                }
                return
            }
            // Flush record changes and deletions for this zone to disk
            // Write this new zone change token to disk
            let tokenData = try! NSKeyedArchiver.archivedData(withRootObject: changeToken as Any, requiringSecureCoding: true)
            UserDefaults.standard.set(tokenData, forKey: "LessonBookZoneChangeToken")

        }
        operation.fetchRecordZoneChangesCompletionBlock = { (error) in
            if let error = error {
                print("Error fetching zone changes for \(databaseTokenKey) database:", error)
            }
            completion()
        }
        database.add(operation)
    }
    
    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        context = persistentContainer.viewContext

        if !(context?.commitEditing())! {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if (context?.hasChanges)! {
            do {
                try context?.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return persistentContainer.viewContext.undoManager
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let context = persistentContainer.viewContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
            return .terminateCancel
        }
        
        if !context.hasChanges {
            return .terminateNow
        }
        
        do {
            try context.save()
        } catch {
            let nserror = error as NSError

            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }

}

