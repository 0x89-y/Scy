@{
    # Scy intentionally uses non-approved PowerShell verbs for its internal UI
    # helpers (Apply-Theme, Render-*, Toggle-*, Build-*, Pump-Splash, etc.).
    # These are private functions, never exported as a module, so the approved-
    # verb convention does not apply. Suppress that one rule so genuine warnings
    # are not buried under dozens of false positives.
    ExcludeRules = @(
        'PSUseApprovedVerbs'
    )
}
