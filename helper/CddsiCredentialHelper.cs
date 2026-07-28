using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

internal static class CddsiCredentialHelper
{
    private const int MinimumLength = 8;
    private const int MaximumLength = 4096;
    private const string EntropyText =
        "claude-desktop-deepseek-installer:deepseek:v1";

    private static int Main()
    {
        byte[] encrypted = null;
        byte[] plaintext = null;
        byte[] entropy = null;
        try
        {
            string root = Path.Combine(
                Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),
                "ClaudeDeepSeekInstaller");
            string credentialPath = Path.Combine(root, "credential.bin");
            FileInfo info = new FileInfo(credentialPath);
            if (!info.Exists || info.Length < 16 || info.Length > 32768)
            {
                return 2;
            }

            encrypted = File.ReadAllBytes(credentialPath);
            entropy = Encoding.UTF8.GetBytes(EntropyText);
            plaintext = ProtectedData.Unprotect(
                encrypted,
                entropy,
                DataProtectionScope.CurrentUser);
            if (plaintext.Length < MinimumLength ||
                plaintext.Length > MaximumLength)
            {
                return 3;
            }

            for (int i = 0; i < plaintext.Length; i++)
            {
                byte value = plaintext[i];
                if (value < 0x21 || value > 0x7e)
                {
                    return 3;
                }
            }

            using (Stream output = Console.OpenStandardOutput())
            {
                output.Write(plaintext, 0, plaintext.Length);
                output.Flush();
            }
            return 0;
        }
        catch
        {
            return 1;
        }
        finally
        {
            if (plaintext != null)
            {
                Array.Clear(plaintext, 0, plaintext.Length);
            }
            if (encrypted != null)
            {
                Array.Clear(encrypted, 0, encrypted.Length);
            }
            if (entropy != null)
            {
                Array.Clear(entropy, 0, entropy.Length);
            }
        }
    }
}
