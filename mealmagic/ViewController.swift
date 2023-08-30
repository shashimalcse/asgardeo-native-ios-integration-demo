//
//  ViewController.swift
//  mealmagic
//
//  Created by Thilina Shashimal Senarath on 2023-08-29.
//

import UIKit
import AppAuthCore
import AppAuth

let authStateKey: String = "authState";

class ViewController: UIViewController {
    
    private var clientId: String!
    private var redirectUri: URL!
    private var authorizeEndpoint: URL!
    private var tokenEndpoint: URL!
    private var logoutEndpoint: URL!
    private var userInfoEndpoint: URL!
    
    @IBOutlet private var signInButton: UIButton!
    @IBOutlet private var logoutButton: UIButton!
    private var asgardeoTextLabel: UILabel!
    private var sampleAppTextLabel: UILabel!
    private var homeScreenTextLabel: UILabel!
    
    private var authState: OIDAuthState?
    
    var currentAuthorizationFlow: OIDExternalUserAgentSession?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.loadOAuthConf()
        self.setupUI()
        self.loadState()
        self.updateUI()
    }

}

// Load config
extension ViewController {
    
    func loadOAuthConf(){
        
        if let plistPath = Bundle.main.path(forResource: "Asgardeo", ofType: "plist") {
            if let plistData = FileManager.default.contents(atPath: plistPath) {
                do {
                    if let plistObject = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                        
                        if let clientId = plistObject["clientId"] as? String {
                            self.clientId = clientId
                        }
                        if let redirectURL = plistObject["redirectURL"] as? String {
                            self.redirectUri = URL(string: redirectURL)
                        }
                        if let authorizeEndpoint = plistObject["authorizeEndpoint"] as? String {
                            self.authorizeEndpoint = URL(string: authorizeEndpoint)
                        }
                        if let tokenEndpoint = plistObject["tokenEndpoint"] as? String {
                            self.tokenEndpoint = URL(string: tokenEndpoint)
                        }
                        if let logoutEndpoint = plistObject["logoutEndpoint"] as? String {
                            self.logoutEndpoint = URL(string: logoutEndpoint)
                        }
                        if let userInfoEndpoint = plistObject["userInfoEndpoint"] as? String {
                            self.userInfoEndpoint = URL(string: userInfoEndpoint)
                        }
                    }
                } catch {
                    print("Error reading plist: \(error)")
                }
            }
        } else {
            print("Plist file not found")
        }
    }
}

// UI Actions Methods
extension ViewController {
    
    @objc func signedInButtonTapped() {
        doAuthWithCodeFlow()
    }
    
    @objc func logoutButtonTapped() {
        
        let alertController = UIAlertController(title: "Are you sure want to logout?",
                                                message: nil,
                                                preferredStyle: UIAlertController.Style.actionSheet)
        let logoutAction = UIAlertAction(title: "Logout", style: .destructive) { (action) in
            self.updateUI()
            self.doCallLogout()
        }
        alertController.addAction(logoutAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (action) in
            
        }
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
    }
}

// Helper Methods
extension ViewController {
    
    // Save authState in UserDefault
    func saveState() {
        
        var data: Data? = nil
        
        if let authState = self.authState {
            do {
                data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: false)
            } catch {
                
            }
        }
        
        if let userDefaults = UserDefaults(suiteName: "magicmeal.corp") {
            userDefaults.set(data, forKey: authStateKey)
            userDefaults.synchronize()
        }
    }
    
    // Load authState in UserDefault
    func loadState() {
        guard let data = UserDefaults(suiteName: "magicmeal.corp")?.object(forKey: authStateKey) as? Data else {
            return
        }
        do {
            if let authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
                self.setAuthState(authState)
            }
        } catch {
            
        }
    }
    
    // Set authState
    func setAuthState(_ authState: OIDAuthState?) {
        if (self.authState == authState) {
            return;
        }
        self.authState = authState;
        self.authState?.stateChangeDelegate = self;
        self.stateChanged()
    }
    
    // Handle authState change
    func stateChanged() {
        self.saveState()
        self.updateUI()
    }
    
    // Update UI when authState chnage
    func updateUI() {
    
        if let authState = self.authState {
            if (authState.isAuthorized) {
                self.moveToHomeScreen()
                self.doGetUserInfo()
            } else {
                self.moveToLoginScreen()
            }
        } else {
            self.moveToLoginScreen()
        }
    }
}

// AppAuth Methods
extension ViewController {
    
    func doAuthWithCodeFlow() {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        
        // builds authentication request
        let request = OIDAuthorizationRequest(configuration: OIDServiceConfiguration(
            authorizationEndpoint: authorizeEndpoint!,
            tokenEndpoint: tokenEndpoint!
        ),
                                              clientId: clientId,
                                              clientSecret: nil,
                                              scopes: [OIDScopeOpenID, OIDScopeProfile],
                                              redirectURL: redirectUri!,
                                              responseType: OIDResponseTypeCode,
                                              additionalParameters: nil)
        
        guard let agent = OIDExternalUserAgentIOS(presenting: self) else {
            return
        }
        // performs authentication request
        appDelegate.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, externalUserAgent: agent){ authState, error in
            
            if let authState = authState {
                self.setAuthState(authState)
            } else {
                self.setAuthState(nil)
            }
        }
    }
    
    func doCallLogout() {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        
        guard let idToken = self.authState?.lastTokenResponse?.idToken else {
            return
        }
        let request = OIDEndSessionRequest(
            configuration:OIDServiceConfiguration(authorizationEndpoint: authorizeEndpoint!, tokenEndpoint: tokenEndpoint!, issuer: nil, registrationEndpoint: nil, endSessionEndpoint: logoutEndpoint!),
            idTokenHint: idToken,
            postLogoutRedirectURL: redirectUri!,
            additionalParameters: nil)
        
        guard let agent = OIDExternalUserAgentIOS(presenting: self) else {
            return
        }
        
        appDelegate.currentAuthorizationFlow = OIDAuthorizationService.present(request,
                                                                externalUserAgent: agent) {response, error in
            if response != nil {
                self.setAuthState(nil)
            } else {
            }

        }
    }
    
    func doGetUserInfo() {
        
        var request = URLRequest(url: userInfoEndpoint!)
        
        guard let accessToken = self.authState?.lastTokenResponse?.accessToken else {
            return
        }
        
        // Add authorization header
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if (httpResponse.statusCode == 401) {
                    self.setAuthState(nil)
                }
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
                if let jsonResponse = jsonResponse as? [String: Any] {
                    DispatchQueue.main.async {
                        if let username = jsonResponse["given_name"] as? String {

                            self.homeScreenTextLabel.text = "Welcome " + username
                        }
                    }
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }
        
        task.resume()
    }

    
}


extension ViewController: OIDAuthStateChangeDelegate, OIDAuthStateErrorDelegate {
    
    func didChange(_ state: OIDAuthState) {
        self.stateChanged()
    }
    
    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        
    }
}

// UI
extension ViewController {
    
    
    func setupUI() {
        
        // Add background text labels
        asgardeoTextLabel = UILabel()
        asgardeoTextLabel.text = "Asgardeo"
        asgardeoTextLabel.textColor = UIColor.black
        asgardeoTextLabel.font = UIFont.boldSystemFont(ofSize: 40)
        asgardeoTextLabel.textAlignment = .center
        asgardeoTextLabel.backgroundColor = UIColor.clear
        asgardeoTextLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(asgardeoTextLabel)
        
        sampleAppTextLabel = UILabel()
        sampleAppTextLabel.text = "Sample Application"
        sampleAppTextLabel.textColor = UIColor.lightGray
        sampleAppTextLabel.font = UIFont.systemFont(ofSize: 15)
        sampleAppTextLabel.textAlignment = .center
        sampleAppTextLabel.backgroundColor = UIColor.clear
        sampleAppTextLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sampleAppTextLabel)
        
        homeScreenTextLabel = UILabel()
        homeScreenTextLabel.textColor = UIColor.black
        homeScreenTextLabel.font = UIFont.boldSystemFont(ofSize: 30)
        homeScreenTextLabel.textAlignment = .center
        homeScreenTextLabel.backgroundColor = UIColor.clear
        homeScreenTextLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(homeScreenTextLabel)
        
        // Add SignIn button
        signInButton = UIButton(type: .system)
        signInButton.setTitle("Login", for: .normal)
        signInButton.setTitleColor(.orange, for: .normal)
        signInButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        signInButton.layer.borderColor = UIColor.orange.cgColor
        signInButton.layer.borderWidth = 2
        signInButton.layer.cornerRadius = 10
        signInButton.addTarget(self, action: #selector(signedInButtonTapped), for: .touchUpInside)
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.isUserInteractionEnabled = true
        
        // Add Logout button
        logoutButton = UIButton(type: .system)
        logoutButton.setTitle("Logout", for: .normal)
        logoutButton.setTitleColor(.white, for: .normal)
        logoutButton.backgroundColor = .orange
        logoutButton.layer.cornerRadius = 10
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.isUserInteractionEnabled = true
        
        view.addSubview(signInButton)
        view.addSubview(logoutButton)
        
        // Hanlde Constains
        asgardeoTextLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        asgardeoTextLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -200).isActive = true
        
        sampleAppTextLabel.centerXAnchor.constraint(equalTo: asgardeoTextLabel.centerXAnchor).isActive = true
        sampleAppTextLabel.centerYAnchor.constraint(equalTo: asgardeoTextLabel.centerYAnchor, constant: 40).isActive = true
        
        signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        signInButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 100).isActive = true
        signInButton.widthAnchor.constraint(equalToConstant: 300).isActive = true
        signInButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        logoutButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100).isActive = true
        logoutButton.widthAnchor.constraint(equalToConstant: 300).isActive = true
        logoutButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        logoutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true

        homeScreenTextLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 200).isActive = true
        homeScreenTextLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20).isActive = true
        homeScreenTextLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20).isActive = true
    }
    
    func moveToLoginScreen() {
        self.signInButton.isEnabled = true
        self.signInButton.isHidden = false
        self.asgardeoTextLabel.isHidden = false
        self.sampleAppTextLabel.isHidden = false
        self.logoutButton.isEnabled = false
        self.logoutButton.isHidden = true
        self.homeScreenTextLabel.isHidden = true
    }
    
    func moveToHomeScreen() {
        self.signInButton.isEnabled = false
        self.signInButton.isHidden = true
        self.asgardeoTextLabel.isHidden = true
        self.sampleAppTextLabel.isHidden = true
        self.logoutButton.isEnabled = true
        self.logoutButton.isHidden = false
        self.homeScreenTextLabel.isHidden = false
    }
}

