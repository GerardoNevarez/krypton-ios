//
//  PairingTests.swift
//  Kryptonite
//
//  Created by Alex Grinman on 3/3/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation

import XCTest
import Sodium
import JSON

class PairingTests: XCTestCase {
    
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    
    func testCreatePairing() {
        do {
            let pk = try KRSodium.shared().box.keyPair()!.publicKey
            let _ = try Pairing(name: "test", workstationPublicKey: pk)
        } catch {
            XCTFail("error: \(error)")
        }
    }
    
    func testWrapPublicKey() {
        
        do {
            let kp = try KRSodium.shared().box.keyPair()!
            let pairing = try Pairing(name: "test", workstationPublicKey: kp.publicKey)
            
            let wrappedPub = try pairing.keyPair.publicKey.wrap(to: kp.publicKey)
            
            // unwrapp pub
            
            let unwrapped = try KRSodium.shared().box.open(anonymousCipherText: wrappedPub, recipientPublicKey: kp.publicKey, recipientSecretKey: kp.secretKey)!
            
            // ensure unwrapped == pairing.publicKey
            
            guard pairing.keyPair.publicKey.toBase64() == unwrapped.toBase64() else {
                XCTFail("Error: non matching unwrapped public key. \nGot: \(unwrapped.toBase64()). Expected: \(pairing.keyPair.publicKey.toBase64())")
                return
            }
        } catch {
            XCTFail("error: \(error)")
        }
    }
    
    func testSeal() {
        
        do {
            
            let kp = try KRSodium.shared().box.keyPair()!
            let pairing = try Pairing(name: "test", workstationPublicKey: kp.publicKey)
            
            let dataStruct = TestStruct(p1: "hello", p2: "world")
            
            let sealed = try dataStruct.seal(to: pairing)
    
            let unsealed = try KRSodium.shared().box.open(nonceAndAuthenticatedCipherText: sealed, senderPublicKey: pairing.keyPair.publicKey, recipientSecretKey: kp.secretKey)!
            
            let dataStructUnsealed = try TestStruct(jsonData: unsealed)
            // ensure sealed == unsealed
            
            guard dataStruct == dataStructUnsealed else {
                XCTFail("Error: non matching structures. \nGot: \(dataStructUnsealed). Expected: \(dataStruct)")
                return
            }
        } catch {
            XCTFail("error: \(error)")
        }
    }
    
    func testUnseal() {
        
        do {
            
            let kp = try KRSodium.shared().box.keyPair()!
            let pairing = try Pairing(name: "test", workstationPublicKey: kp.publicKey)
            
            let dataStruct = TestStruct(p1: "hello", p2: "world")
            
            let sealed:Data = try KRSodium.shared().box.seal(message: dataStruct.jsonData(), recipientPublicKey: pairing.keyPair.publicKey, senderSecretKey: kp.secretKey)!
            
            let unsealed = try TestStruct(from: pairing, sealed: sealed)
            
            // ensure sealed == unsealed
            guard dataStruct == unsealed else {
                XCTFail("Error: non matching structures. \nGot: \(unsealed). Expected: \(dataStruct)")
                return
            }
        } catch {
            XCTFail("error: \(error)")
        }
    }
    
}

struct TestStruct:Jsonable {
    var param1:String
    var param2:String
    
    init(p1:String, p2:String) {
        self.param1 = p1
        self.param2 = p2
    }
    
    init(json: Object) throws {
        param1 = try json ~> "1"
        param2 = try json ~> "2"
    }
    
    var object: Object {
        return ["1": param1, "2": param2]
    }
}

func ==(l:TestStruct, r:TestStruct) -> Bool {
    return l.param1 == r.param1 && l.param2 == r.param2
}


