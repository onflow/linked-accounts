import MetadataViews from "./utility/MetadataViews.cdc"

/// Metadata views relevant to identifying information about linked accounts
///
pub contract LinkedAccountMetadataViews {

    /// Identifies information that could be used to determine the off-chain
    /// associations of a child account
    ///
    pub struct interface LinkedAccountMetadata {
        pub let name: String
        pub let description: String
        pub let icon: AnyStruct{MetadataViews.File}
        pub let externalURL: MetadataViews.ExternalURL
    }

    /// Simple metadata struct containing the most basic information about a
    /// linked account
    pub struct LinkedAccountInfo : LinkedAccountMetadata {
        pub let name: String
        pub let description: String
        pub let icon: AnyStruct{MetadataViews.File}
        pub let externalURL: MetadataViews.ExternalURL
        
        init(
            name: String,
            description: String,
            icon: AnyStruct{MetadataViews.File},
            externalURL: MetadataViews.ExternalURL
        ) {
            self.name = name
            self.description = description
            self.icon = icon
            self.externalURL = externalURL
        }
    }
}