//
//  Policy.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/14/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation



class Policy {
    
    enum Interval:TimeInterval {
        //case fifteenSeconds = 15
        case oneHour = 3600 
    }

    
    //MARK: Settings
    enum StorageKey:String {
        case userApproval = "policy_user_approval"
        case userLastApproved = "policy_user_last_approved"
        case userApprovalInterval = "policy_user_approval_interval"
        
        func key(id:String) -> String {
            return "\(self.rawValue)_\(id)"
        }

    }
    
    class func set(needsUserApproval:Bool, for session:Session) {
        UserDefaults.standard.set(needsUserApproval, forKey: StorageKey.userApproval.key(id: session.id))
        UserDefaults.standard.removeObject(forKey: StorageKey.userLastApproved.key(id: session.id))
        UserDefaults.standard.removeObject(forKey: StorageKey.userApprovalInterval.key(id: session.id))
        UserDefaults.standard.synchronize()
    }
    
    class func needsUserApproval(for session:Session) -> Bool {
        let needsApproval =  UserDefaults.standard.bool(forKey: StorageKey.userApproval.key(id: session.id))
        
        if  let lastApproved = UserDefaults.standard.object(forKey: StorageKey.userLastApproved.key(id: session.id)) as? Date
        {
            let approvalInterval = UserDefaults.standard.double(forKey: StorageKey.userApprovalInterval.key(id: session.id))
            
            return -lastApproved.timeIntervalSinceNow > approvalInterval
            
        }
        return needsApproval
    }

    class func approvedUntil(for session:Session) -> Date? {
        if  let lastApproved = UserDefaults.standard.object(forKey: StorageKey.userLastApproved.key(id: session.id)) as? Date
        {
            let approvalInterval = UserDefaults.standard.double(forKey: StorageKey.userApprovalInterval.key(id: session.id))
            
            return lastApproved.addingTimeInterval(approvalInterval)
            
        }
        
        return nil
    }

    class func approvedUntilUnixSeconds(for session:Session) -> Int? {
        if let time = Policy.approvedUntil(for: session)?.timeIntervalSince1970 {
            return Int(time)
        }
        return nil
    }

    class func approvalTimeRemaining(for session:Session) -> String? {
        if  let lastApproved = UserDefaults.standard.object(forKey: StorageKey.userLastApproved.key(id: session.id)) as? Date
        {
            let approvalInterval = UserDefaults.standard.double(forKey: StorageKey.userApprovalInterval.key(id: session.id))
            
            if -lastApproved.timeIntervalSinceNow > approvalInterval {
                return nil
            }
            
            return lastApproved.addingTimeInterval(approvalInterval + lastApproved.timeIntervalSinceNow).timeAgo(suffix: "")
        }
        
        return nil

    }
    
    static var currentViewController:UIViewController?
    
    static func allow(session:Session, for time:Interval) {
        UserDefaults.standard.set(Date(), forKey: StorageKey.userLastApproved.key(id: session.id))
        UserDefaults.standard.set(time.rawValue, forKey: StorageKey.userApprovalInterval.key(id: session.id))
        UserDefaults.standard.synchronize()
    }
    
    //MARK: Pending request
    
    static var pendingAuthorization:(Session, Request)?
    
    //MARK: Notification Actions

    static var authorizeCategory:UIUserNotificationCategory = {
        let cat = UIMutableUserNotificationCategory()
        cat.identifier = "authorize_identifier"
        cat.setActions([Policy.approveAction, Policy.approveTemporaryAction, Policy.rejectAction], for: UIUserNotificationActionContext.default)
        return cat
        
    }()

    static let approveIdentifier = "approve_identifier"
    
    static var approveAction:UIMutableUserNotificationAction = {
        var approve = UIMutableUserNotificationAction()
        
        approve.identifier = approveIdentifier
        approve.title = "Allow once"
        approve.activationMode = UIUserNotificationActivationMode.background
        approve.isDestructive = false
        approve.isAuthenticationRequired = true
        
        return approve
    }()


    static let approveTempIdentifier = "approve_temp_identifier"
    static var approveTemporaryAction:UIMutableUserNotificationAction = {
        var approve = UIMutableUserNotificationAction()
        
        approve.identifier = approveTempIdentifier
        approve.title = "Allow for 1 hour"
        approve.activationMode = UIUserNotificationActivationMode.background
        approve.isDestructive = false
        approve.isAuthenticationRequired = true
        
        return approve
    }()

    static let rejectIdentifier = "reject_identifier"
    static var rejectAction:UIMutableUserNotificationAction = {
        var reject = UIMutableUserNotificationAction()
        
        reject.identifier = rejectIdentifier
        reject.title = "Reject"
        reject.activationMode = UIUserNotificationActivationMode.background
        reject.isDestructive = true
        reject.isAuthenticationRequired = false
        
        return reject
    }()
    
    //MARK: Notification Push

    class func requestUserAuthorization(session:Session, request:Request) {
        
        guard UIApplication.shared.applicationState != .inactive else {
            dispatchAfter(delay: 1.0, task: { 
                Policy.requestUserAuthorization(session: session, request: request)
            })
            return
        }
        
        guard UIApplication.shared.applicationState != .active else {
            Policy.pendingAuthorization = nil
            Policy.currentViewController?.requestUserAuthorization(session: session, request: request)
            return
        }
        
        // set the pending
        Policy.pendingAuthorization = (session, request)
        
        // present notification
        let notification = UILocalNotification()
        notification.alertBody = "Request from \(session.pairing.displayName): \(request.sign?.command ?? "SSH login")"
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.category = Policy.authorizeCategory.identifier
        notification.userInfo = ["session_id": session.id, "request": request.object]

        UIApplication.shared.presentLocalNotificationNow(notification)
    }
    
    class func notifyUser(session:Session, request:Request) {
        guard UIApplication.shared.applicationState != .active else {
            Policy.currentViewController?.showApprovedRequest(session: session, request: request)
            return
        }
        
        let notification = UILocalNotification()

        notification.alertBody = "\(session.pairing.displayName): \(request.sign?.command ?? "SSH login")"
        notification.soundName = UILocalNotificationDefaultSoundName

        UIApplication.shared.presentLocalNotificationNow(notification)
    }
}

extension UIViewController {
    
    
    func requestUserAuthorization(session:Session, request:Request) {

        let approvalController = Resources.Storyboard.Approval.instantiateViewController(withIdentifier: "ApproveController")
        approvalController.modalTransitionStyle = UIModalTransitionStyle.coverVertical
        approvalController.modalPresentationStyle = UIModalPresentationStyle.overFullScreen
        
        (approvalController as? ApproveController)?.session = session
        (approvalController as? ApproveController)?.request = request
        
        dispatchMain {
            self.present(approvalController, animated: true, completion: nil)
        }
    }
    
    func showApprovedRequest(session:Session, request:Request) {
        
        let autoApproveController = Resources.Storyboard.Approval.instantiateViewController(withIdentifier: "AutoApproveController")
        autoApproveController.modalTransitionStyle = UIModalTransitionStyle.coverVertical
        autoApproveController.modalPresentationStyle = UIModalPresentationStyle.overFullScreen
        
        (autoApproveController as? AutoApproveController)?.deviceName = session.pairing.displayName.uppercased()
        (autoApproveController as? AutoApproveController)?.command = request.sign?.command ?? "Unknown"

        
        dispatchMain {
            self.present(autoApproveController, animated: true, completion: nil)
        }
    }
}

