public func resolveAppGroupID(infoDictionary: [String: Any], fallback: String = "group.com.mibanco.shared") -> String {
    (infoDictionary["ALTAppGroups"] as? [String])?.first ?? fallback
}
