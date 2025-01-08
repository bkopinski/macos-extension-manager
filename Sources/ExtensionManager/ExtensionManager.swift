//
//  ExtensionManager.swift
//  ExtensionManager
//
//  Created by Brandon Kopinski on 12/30/24.
//

import SwiftUI
import SystemExtensions


public struct ExtensionManager: View {
    ///The `ExtensionController` to view.
    var controller: ExtensionController
    
    ///Activation toggle binding. See ExtensionManager() for description.
    @Binding public var activationEnabled: Bool
    
    @State private var isDisabled = true
    @State private var showBundleVersion = false
    @State private var activated = false
    @State private var additionalStatusString: String? = nil
    
    
    /// Initialize an `ExtensionManager` instance to manage and view the
    /// given `ExtensionManager`.
    /// - Parameters:
    ///  - controller: The `ExtensionController` instance that will
    ///  be 'viewed'.
    ///  - activationEnabled: Binding mapped to the activation toggle, which
    ///  allows activation of the managed extension. When changes to true, the
    ///  extension has been activated. When changes to false, the extension
    ///  has been deactivated. Applications are responsible for determining
    ///  the initial state of the toggle. If `activationEnabled` is initially
    ///  true, the extension will be activated automatically during
    ///  initialization of the view. If `activationEnabled` is false, the
    ///  extension will be deactivated (if currently activated). It is
    ///  recommended that the application track when activation should be
    ///  allowed and initialize activationEnabled to reflect the desired
    ///  activation setting.
    public init(controller: ExtensionController,
                activationEnabled: Binding<Bool>) {
        self.controller = controller
        self._activationEnabled = activationEnabled
    }
    
    
    public var body: some View {
        VStack {
            Toggle(isOn: $activationEnabled) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(controller.displayName)")
                            .fontWeight(.semibold)
                            .fixedSize()
                        Text("Version \(controller.bundleShortVersion)\(showBundleVersion ? " (\(controller.bundleVersion))" : "")")
                            .font(.caption)
                            .onTapGesture(count: 2) {
                                showBundleVersion = !showBundleVersion
                            }
                        HStack {
                            Text("Activate the \(controller.isDext ? "Driver" : "System") Extension")

                            if let addStatus = additionalStatusString {
                                Text("(\(addStatus))")
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .disabled(isDisabled)
            .onChange(of: activationEnabled) { oldValue, newValue in
                isDisabled = true
                
                if oldValue != newValue {
                    if newValue && !activated {
                        handleActivate()
                        return
                    } else if !newValue && activated {
                        handleDeactivate()
                        return
                    }
                }
                
                isDisabled = false
            }
        }
        .onAppear {
            isDisabled = true

            controller.update { status, error in
                if error == nil {
                    // Execute initial activation/deactivation action
                    if activationEnabled {
                        handleActivate()
                    } else if !activationEnabled && controller.activated {
                        handleDeactivate()
                    }
                }
            }
        }
    }
    
    
    private func requestUpdateHandler(status: ExtensionController.RequestStatus,
                                      error: OSSystemExtensionError?,
                                      activate: Bool) {
        additionalStatusString = nil
        
        switch status {
        case .requiresUserApproval:
            additionalStatusString = "Awaiting User Approval"
        case .completedWithError:
            activationEnabled = activated
            isDisabled = false
        case .willCompleteAfterReboot:
            additionalStatusString = "\(activate ? "Activation" : "Deactivation") Requires Reboot"
            fallthrough
        case .completed:
            fallthrough
        case .unknown:
            activated = activate
            isDisabled = false
        }
    }
    
    
    private func handleActivate() {
        controller.activate { status, error in
            requestUpdateHandler(status: status, error: error, activate: true)
        }
    }

    
    private func handleDeactivate() {
        controller.deactivate { status, error in
            requestUpdateHandler(status: status, error: error, activate: false)
        }
    }
}
