@{
    SchemaVersion = 3
    Contract       = 'D-027-practical-v1'

    Functions = @(
        @{
            Name                = 'Invoke-CddsiDryRun'
            File                = 'lib/workflow.ps1'
            MandatoryParameters = @('Action')
            ActionValidateSet   = @('Install', 'Diagnose', 'Restore')
        }
        @{
            Name                = 'Invoke-CddsiAction'
            File                = 'lib/workflow.ps1'
            MandatoryParameters = @('Action', 'ProjectRoot')
            ActionValidateSet   = @('Install', 'Diagnose', 'Restore')
        }
    )
}
