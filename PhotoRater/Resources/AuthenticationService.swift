//
//  AuthenticationService.swift
//  PhotoRater
//
//  Created by David Harms on 4/19/25.
//

import Foundation
import FirebaseAuth

class AuthenticationService {
    static let shared = AuthenticationService()
    
    private init() {}
    
    var currentUser: User? {
        return Auth.auth().currentUser
    }
    
    func signInAnonymously(completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let user = authResult?.user else {
                completion(.failure(NSError(domain: "AuthenticationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user returned from anonymous sign in"])))
                return
            }
            
            completion(.success(user))
        }
    }
    
    func ensureAuthenticated(completion: @escaping (Result<Void, Error>) -> Void) {
        if currentUser != nil {
            completion(.success(()))
        } else {
            signInAnonymously { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
