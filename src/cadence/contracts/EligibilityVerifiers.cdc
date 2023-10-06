// EligibilityVerifiers are used to check the eligibility of accounts
// With drizzle, you can decide who is eligible for your rewards by using our different modes.
// 1. FLOAT Event. You can limit the eligibility to people who own FLOATs of specific FLOAT Event at the time of the DROP being created.
// 2. Whitelist. You can upload a whitelist. Only accounts on the whitelist are eligible for rewards.

import FungibleToken from "./core/FungibleToken.cdc"
import FLOAT from "./float/FLOAT.cdc"

pub contract EligibilityVerifiers {

    pub enum VerifyMode: UInt8 {
        pub case oneOf
        pub case all
    }

    pub struct VerifyResultV2 {
        pub let isEligible: Bool
        pub let usedNFTs: [UInt64]
        pub let extraData: {String: AnyStruct}

        init(isEligible: Bool, usedNFTs: [UInt64], extraData: {String: AnyStruct}) {
            self.isEligible = isEligible
            self.usedNFTs = usedNFTs
            self.extraData = extraData
        }
    }

    pub struct interface INFTRecorder {
        pub let usedNFTs: {UInt64: Address}

        pub fun addUsedNFTs(account: Address, nftTokenIDs: [UInt64])
    }

    pub struct interface IEligibilityVerifier {
        pub let type: String

        pub fun verify(account: Address, params: {String: AnyStruct}): VerifyResultV2
    }

    pub struct FLOATEventData {
        pub let host: Address
        pub let eventID: UInt64

        init(host: Address, eventID: UInt64) {
            self.host = host
            self.eventID = eventID
        }
    }

    pub struct Whitelist: IEligibilityVerifier {
        pub let whitelist: {Address: AnyStruct}
        pub let type: String

        init(whitelist: {Address: AnyStruct}) {
            self.whitelist = whitelist
            self.type = "Whitelist"
        }

        pub fun verify(account: Address, params: {String: AnyStruct}): VerifyResultV2 {
            return VerifyResultV2(
                isEligible: self.whitelist[account] != nil,
                usedNFTs: [],
                extraData: {}
            )
        }
    }

    pub struct FLOATsV2: IEligibilityVerifier, INFTRecorder {
        pub let events: [FLOATEventData]
        pub let threshold: UInt32
        pub let mintedBefore: UFix64
        pub let type: String
        pub let usedNFTs: {UInt64: Address}

        init(
            events: [FLOATEventData],
            mintedBefore: UFix64,
            threshold: UInt32
        ) {
            pre {
                threshold > 0: "Threshold should greater than 0"
                events.length > 0: "Events should not be empty"
            }

            self.events = events 
            self.threshold = threshold
            self.mintedBefore = mintedBefore
            self.type = "FLOATs"
            self.usedNFTs = {}
        }

        pub fun verify(account: Address, params: {String: AnyStruct}): VerifyResultV2 {
            let floatCollection = getAccount(account)
                .getCapability(FLOAT.FLOATCollectionPublicPath)
                .borrow<&FLOAT.Collection{FLOAT.CollectionPublic}>()

            if floatCollection == nil {
                return VerifyResultV2(isEligible: false, usedNFTs: [], extraData: {})
            }

            let validFLOATs: [UInt64] = []
            for _event in self.events {
                let ownedIDs = floatCollection!.ownedIdsFromEvent(eventId: _event.eventID)
                for floatID in ownedIDs {
                    if self.usedNFTs[floatID] == nil {
                        if let float = floatCollection!.borrowFLOAT(id: floatID) {
                            if float.dateReceived <= self.mintedBefore {
                                validFLOATs.append(floatID)
                                if UInt32(validFLOATs.length) >= self.threshold {
                                    return VerifyResultV2(isEligible: true, usedNFTs: validFLOATs, extraData: {})
                                }
                            }
                        }
                    }
                }
            }
            return VerifyResultV2(isEligible: false, usedNFTs: [], extraData: {})
        }

        pub fun addUsedNFTs(account: Address, nftTokenIDs: [UInt64]) {
            for tokenID in nftTokenIDs {
                self.usedNFTs[tokenID] = account
            }
        }
    }
}
