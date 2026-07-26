@{
    SchemaVersion = 1
    ContractVersion = 'cddsi-d027-snapshot-authority-policy-v1'

    # Live D-027 operations remain deliberately unavailable until an external
    # VM operator provisions one exact public key and changes Configured to
    # $true in a reviewed candidate.  The corresponding private key must never
    # enter this repository, candidate ZIP, guest VM, logs, or evidence.
    Configured = $false
    AuthorityId = '<UNCONFIGURED_D027_EXTERNAL_VM_OPERATOR_AUTHORITY>'
    SignatureAlgorithm = 'RSA-SHA256-PKCS1-v1_5'
    AuthorityKeySha256 = '0000000000000000000000000000000000000000000000000000000000000000'
    RsaModulusBase64 = ''
    RsaExponentBase64 = ''
}
