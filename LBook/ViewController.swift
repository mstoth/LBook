//
//  ViewController.swift
//  LBook
//
//  Created by Michael Toth on 3/25/19.
//  Copyright © 2019 Michael Toth. All rights reserved.
//

import Cocoa
import CloudKit
import CoreData


class ViewController: NSViewController {

    @objc dynamic var context:NSManagedObjectContext? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let delegate = NSApplication.shared.delegate as! AppDelegate
        self.context = delegate.persistentContainer.viewContext
        // let student = Student(context: context)
        
        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "lessonSegue" {
            let c = segue.destinationController as! LessonViewController
            c.context = context
        }
    }

}

