//
//  ExtensionController.swift
//  ExtensionManager
//
//  Created by Brandon Kopinski on 1/7/25.
//

import Foundation
import SystemExtensions
import os.log


public class ExtensionController: NSObject, OSSystemExtensionRequestDelegate {
    /// Bundle identifier of the System Extension to manage.
    public var bundleIdentifier: String
    
    /// CFBundleVersion of the System Extension. Defaults to empty
    /// string.
    public var bundleVersion: String
    
    /// CFBundleShortVersionString of the System Extension. Defaults to empty
    /// string.
    public var bundleShortVersion: String
    
    /// Display name of the System Extension. The string will be either
    /// CFBundleDisplayName, CFBundleName, or the given `bundleIdentifier`,
    /// depending on the existence of the above keys in the extension's bundle Info.plist.
    public var displayName: String
    
    /// Indicates if the System Extension is a Driver Extension.
    public var isDext: Bool
    
    /// Indicates if the System Extension has been activated. This property
    /// should be read after the update request completes.
    public var activated: Bool = false
    
    
    private var queue: DispatchQueue
    private var requests: [OSSystemExtensionRequest: RequestContext] = [:]
    
    
    /// Possible statuses of an extension request, started by `activate` or
    /// `deactivate`.
    /// - Parameters:
    ///   - completed: The request has completed.
    ///   - completedWithError: The request completed with error. In this case,
    ///   `RequestContext.error` is not nil.
    ///   - requiresUserApproval: The request requires user approval. In this
    ///   case the request has not yet completed, and the caller should expect the
    ///   given `RequestUpdate` callback to be called again.
    ///   - unknown: The request finished with an unknown status.
    ///   - willCompleteAfterReboot: The request will complete after a reboot
    public enum RequestStatus {
        case requiresUserApproval
        case completed
        case completedWithError
        case willCompleteAfterReboot
        case unknown
    }
    
    
    /// Request update callback type. This callback may be executed multiple
    /// times synchronously to report on the status of the submitted request.
    public typealias RequestUpdate = ((RequestStatus, OSSystemExtensionError?) -> ())
    
    
    /// The types of extension requests supported by `ExtensionController`
    private enum RequestType {
        case activate
        case deactivate
        case update
    }
    
    
    /// Context data for the submitted request
    private struct RequestContext {
        var type: RequestType
        var callback: RequestUpdate
    }
    
    
    /// Initialize an `ExtensionController` instance to manage System Extension
    /// activation requests.
    /// - Parameters:
    ///  - bundleIdentifier: The bundle identifier of the System Extension to
    ///  manage.
    ///  - queue: The dispatch queue that the `RequestUpdate` callbacks will
    ///  be executed on. Clients should also call `activation`, `deactivation`,
    ///  and `update` on the same dispatch queue.
    public init?(bundleIdentifier: String, queue: DispatchQueue) {
        self.bundleIdentifier = bundleIdentifier
        self.queue = queue

        if let bundle = findSystemExtensionBundle(in: Bundle.main, with: bundleIdentifier) {
            if let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                self.bundleVersion = version
            } else {
                self.bundleVersion = ""
                os_log("System extension does not specify CFBundleVersion")
            }
            
            if let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                self.bundleShortVersion = shortVersion
            } else {
                self.bundleShortVersion = ""
                os_log("System extension does not specify CFBundleShortVersionString")
            }
            
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                self.displayName = displayName
            } else if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                self.displayName = bundleName
            } else {
                self.displayName = bundleIdentifier
            }
            
            self.isDext = false
            if let packageType = bundle.object(forInfoDictionaryKey:"CFBundlePackageType") as? String {
                if packageType == "DEXT" {
                    self.isDext = true;
                }
            } else {
                os_log("Unable to determine system extension package type")
            }
        } else {
            os_log("Unable to find system extension with bundle identifier: %@",
                   self.bundleIdentifier)
            return nil
        }
                
        super.init()
    }
    
    
    /// Start an activation request for the managed System Extension
    ///
    /// - Parameters:
    ///  - callback: `RequestUpdate` callback to be called one or more times
    ///  to report status changes to the request.
    public func activate(callback: @escaping RequestUpdate) {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: bundleIdentifier, queue: queue)
        request.delegate = self
        
        self.requests[request] = RequestContext(type: RequestType.activate,
                                                callback: callback)
        
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    
    /// Start a deactivation request for the managed System Extension
    ///
    /// - Parameters:
    ///  - callback: `RequestUpdate` callback to be called one or more times
    ///  to report status changes to the request.
    public func deactivate(callback: @escaping RequestUpdate) {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: bundleIdentifier, queue: queue)
        request.delegate = self
        
        self.requests[request] = RequestContext(type: RequestType.deactivate,
                                                callback: callback)
        
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    
    /// Update the current activation state of the System Extension managed by
    /// the controller.
    ///
    /// - Parameters:
    ///  - callback: `RequestUpdate` callback to be called when the update
    ///  request has been completed
    public func update(callback: @escaping RequestUpdate) {
        let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: bundleIdentifier, queue: queue)
        request.delegate = self
        
        self.requests[request] = RequestContext(type: RequestType.update,
                                                callback: callback)
        
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    
    public func request(_ request: OSSystemExtensionRequest,
                        actionForReplacingExtension existing: OSSystemExtensionProperties,
                        withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        os_log(
            """
            Replacing \(existing.bundleIdentifier) \(existing.bundleShortVersion) (\(existing.bundleVersion))
            with \(ext.bundleIdentifier) \(ext.bundleShortVersion) (\(ext.bundleVersion))
            """
        )
        return .replace
    }
    
    
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("Approval required for system extension (\(self.bundleIdentifier)) request")
        
        if let context = requests[request] {
            context.callback(.requiresUserApproval, nil)
        }
    }
    
    
    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        os_log("System extension (\(self.bundleIdentifier)) request finished with result: \(result.rawValue)")
        
        if let context = requests[request] {
            var status: RequestStatus
            
            requests.removeValue(forKey: request)
            
            switch result {
            case .completed:
                status = .completed
            case .willCompleteAfterReboot:
                status = .willCompleteAfterReboot
            @unknown default:
                status = .unknown
            }
            
            activated = (context.type == .activate)
            
            context.callback(status, nil)
        }
    }
    
    
    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        os_log("System extension (\(self.bundleIdentifier)) request failed with error: \(error.localizedDescription)")
        
        if let context = requests[request] {
            requests.removeValue(forKey: request)
            context.callback(.completedWithError, error as? OSSystemExtensionError)
        }
    }
    
    
    public func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        os_log("System extension properties request completed")
        
        if let context = requests[request], context.type == .update {
            activated = false
            
            for extProp in properties {
                if extProp.bundleIdentifier == bundleIdentifier
                    && extProp.bundleVersion == bundleVersion
                    && extProp.bundleShortVersion == bundleShortVersion {
                    /* When developer mode is enabled, there can be multiple
                     entries for the same extension. If one is found that
                     doesn't require user approval or isn't uninstalling,
                     the extension is assumed to be activated.
                     
                     In macOS 15.2, there is a bug where updating an extension
                     puts the previous one in a "terminating for update via
                     delegate" state, which will also appear as activated with
                     this logic. It is not marked as 'uninstalling' or
                     'awaiting user approval', just like the latest activated
                     entry. Also, this bug will cause subsequent activation and
                     deactivation requests to fail. Clear the database or
                     reboot before trying again.
                     */
                    
                    if !extProp.isUninstalling && !extProp.isAwaitingUserApproval {
                        activated = true
                    }
                }
            }
            
            context.callback(.completed, nil)
        }
    }
}


private func findSystemExtensionBundle(in bundle: Bundle, with bundleIdentifier: String) -> Bundle? {
    let fm = FileManager.default
    let path = bundle.bundlePath + "/Contents/Library/SystemExtensions/"
    do {
        let extensions = try fm.contentsOfDirectory(atPath: path)

        for ext in extensions {
            if let bundle = Bundle(path: path + ext) {
                if let id = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String {
                    if id == bundleIdentifier {
                        return bundle
                    }
                }
            }
        }
    } catch let error {
        os_log("Unable to search SystemExtensions Library: %@",
               error.localizedDescription)
    }
    
    return nil
}
