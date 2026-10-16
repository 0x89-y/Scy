@{
    # Rules that don't fit a WPF app built from private script functions and
    # event handlers. Everything else is enforced: CI (Tests\Invoke-ScyChecks.ps1)
    # fails on any remaining finding.
    ExcludeRules = @(
        # Internal UI helpers (Apply-Theme, Render-*, Toggle-*, Build-*, ...) are
        # private, never exported as a module, so verb/noun conventions don't apply.
        'PSUseApprovedVerbs'
        'PSUseSingularNouns'

        # UI helpers named Set-*/Update-*/New-* change controls, not system state;
        # -WhatIf/-Confirm support would be meaningless for them.
        'PSUseShouldProcessForStateChangingFunctions'

        # WPF event handlers must declare ($sender, $e) even when they only use one.
        'PSReviewUnusedParameter'

        # Positional calls of internal helpers ("Show-ThemedDialog $msg $title ...")
        # are the established style here; informational only.
        'PSAvoidUsingPositionalParameters'

        # A handful of $global: variables are deliberate: event-subscriber actions
        # and dispatcher callbacks run in their own scope (see comments at each use).
        'PSAvoidGlobalVars'

        # install.ps1 is an interactive console installer: Write-Host is its output.
        'PSAvoidUsingWriteHost'

        # Empty catches are best-effort probes (optional data, cleanup); failures
        # that matter are logged with Write-ScyLog or shown to the user.
        'PSAvoidUsingEmptyCatchBlock'

        # Wi-Fi keys and generated passwords are shown to the user on purpose;
        # a SecureString would only be converted straight back.
        'PSAvoidUsingPlainTextForPassword'
    )
}
