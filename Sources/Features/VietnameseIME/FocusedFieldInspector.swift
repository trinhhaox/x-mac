import ApplicationServices

/// Tells single-line fields (URL bars, search boxes) from rich editors. Only
/// single-line fields inline-autocomplete with a selected suggestion, and only
/// they tolerate the autocomplete breaker; contentEditable editors such as
/// Google Docs corrupt it.
enum FocusedFieldInspector {
    static let singleLineRoles: Set<String> = [
        kAXTextFieldRole as String, kAXComboBoxRole as String, "AXSearchField"
    ]
    /// Bound for each of the two Accessibility round trips from the tap thread.
    static let messagingTimeout: Float = 0.015

    private static let roleAttributes = [
        kAXRoleAttribute, kAXSubroleAttribute, "AXEditableAncestor"
    ] as CFArray

    /// Firefox starts its whole accessibility service as soon as an outside
    /// client queries it, which slows it down for the rest of the session.
    static func canProbe(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return !bundleIdentifier.hasPrefix("org.mozilla.")
    }

    /// Rich editors exposed as ARIA textbox/combobox also report AXTextField
    /// or AXComboBox, but carry an editable ancestor or a custom subrole.
    static func isSingleLine(role: String?, subrole: String?, hasEditableAncestor: Bool) -> Bool {
        guard let role, singleLineRoles.contains(role), !hasEditableAncestor else { return false }
        return subrole == nil || subrole == "AXSearchField"
    }

    /// False when the app does not answer in time: replacing without the
    /// breaker is the behaviour that already works outside URL bars.
    static func isSingleLineFieldFocused(processIdentifier: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        // One round trip for all three; missing attributes come back as AXValue errors.
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, roleAttributes, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 3
        else { return false }
        return isSingleLine(
            role: values[0] as? String,
            subrole: values[1] as? String,
            hasEditableAncestor: CFGetTypeID(values[2]) == AXUIElementGetTypeID()
        )
    }
}
