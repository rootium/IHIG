package ihig.apksigner;

import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;

/**
 * A drop-in stand-in for the Android SDK's {@code apksigner} command, built on
 * the {@code apksig} library from Maven Central.
 *
 * <p>It exists because the Android SDK is distributed exclusively from
 * dl.google.com, which some build environments cannot reach. Godot shells out
 * to {@code apksigner} during an Android export and only ever uses three
 * invocations, all of which are implemented here:
 *
 * <pre>
 *   apksigner --version
 *   apksigner sign --verbose --ks K --ks-pass pass:P --ks-key-alias A app.apk
 *   apksigner verify --verbose app.apk
 * </pre>
 *
 * <p>Signing is APK Signature Scheme v2 only, which every Android release
 * since 7.0 (API 24) verifies. Godot refuses to build for anything below API
 * 24, so v2 covers every device its output can run on.
 *
 * <p>v1 (JAR) signing is off by default and cannot be re-enabled in practice:
 * the apksig published to Maven Central builds its PKCS#7 block through
 * {@code sun.security.pkcs.PKCS7.encodeSignedData}, which no longer exists in
 * JDK 9+. The flag is still parsed so callers do not break, and asking for it
 * produces a clear error rather than a stack trace. v3/v4 postdate this library
 * version entirely; those flags are accepted and ignored.
 *
 * <p>Alignment is deliberately not touched. Godot zipaligns its output before
 * calling this tool, and apksig preserves existing entry alignment.
 */
public final class ApkSignerCli {

    private static final String VERSION = "0.1.0-ihig (apksig 2.3.0, v2 signing)";
    private static final int FALLBACK_MIN_SDK = 24;

    /** Flags that consume the following argument. */
    private static final List<String> VALUE_FLAGS = Arrays.asList(
            "--ks", "--ks-pass", "--ks-key-alias", "--ks-key-pass", "--key-pass",
            "--ks-type", "--ks-provider-name", "--ks-provider-class", "--ks-provider-arg",
            "--min-sdk-version", "--max-sdk-version", "--out",
            "--v1-signing-enabled", "--v2-signing-enabled",
            "--v3-signing-enabled", "--v4-signing-enabled",
            "--debuggable-apk-permitted");

    /** Flags that stand alone. */
    private static final List<String> BARE_FLAGS = Arrays.asList("--verbose", "-v", "--help", "-h");

    public static void main(String[] args) {
        try {
            System.exit(run(args));
        } catch (Exception e) {
            System.err.println("apksigner: " + e.getMessage());
            System.exit(1);
        }
    }

    private static int run(String[] args) throws Exception {
        for (String a : args) {
            if (a.equals("--version")) {
                System.out.println(VERSION);
                return 0;
            }
        }
        if (args.length == 0) {
            usage();
            return 1;
        }
        switch (args[0]) {
            case "sign":
                return sign(args);
            case "verify":
                return verify(args);
            case "help":
            case "--help":
            case "-h":
                usage();
                return 0;
            default:
                System.err.println("apksigner: unsupported command '" + args[0] + "'");
                usage();
                return 1;
        }
    }

    private static void usage() {
        System.err.println("usage: apksigner sign   [--ks K] [--ks-pass SPEC] [--ks-key-alias A] [--out O] APK");
        System.err.println("       apksigner verify [--min-sdk-version N] APK");
        System.err.println("       apksigner --version");
    }

    // --- sign ----------------------------------------------------------------

    private static int sign(String[] args) throws Exception {
        Args a = Args.parse(args);
        if (a.positional.isEmpty()) {
            System.err.println("apksigner: no APK given");
            return 1;
        }
        File input = new File(a.positional.get(0));
        if (!input.isFile()) {
            System.err.println("apksigner: no such file: " + input);
            return 1;
        }
        if (a.get("--ks") == null) {
            System.err.println("apksigner: --ks is required");
            return 1;
        }

        char[] storePass = password(a.get("--ks-pass"));
        String keyPassSpec = a.get("--ks-key-pass") != null ? a.get("--ks-key-pass") : a.get("--key-pass");
        char[] keyPass = keyPassSpec != null ? password(keyPassSpec) : storePass;

        KeyStore ks = loadKeyStore(new File(a.get("--ks")), a.get("--ks-type"), storePass);
        String alias = a.get("--ks-key-alias");
        if (alias == null) {
            alias = firstAlias(ks);
        }
        PrivateKey key = (PrivateKey) ks.getKey(alias, keyPass);
        if (key == null) {
            throw new IllegalArgumentException("no private key for alias '" + alias + "' in keystore");
        }
        Certificate[] chain = ks.getCertificateChain(alias);
        if (chain == null || chain.length == 0) {
            throw new IllegalArgumentException("no certificate chain for alias '" + alias + "'");
        }
        List<X509Certificate> certs = new ArrayList<>(chain.length);
        for (Certificate c : chain) {
            certs.add((X509Certificate) c);
        }

        if (a.getBool("--v1-signing-enabled", false)) {
            System.err.println("apksigner: v1 (JAR) signing is not supported by this build — "
                    + "apksig " + "2.3.0 needs sun.security internals that JDK 9+ removed. "
                    + "v2 alone is valid for minSdk 24 and above.");
            return 1;
        }

        ApkSigner.SignerConfig signer =
                new ApkSigner.SignerConfig.Builder("CERT", key, certs).build();

        File output = a.get("--out") != null ? new File(a.get("--out")) : null;
        // apksig cannot read and write the same file, so an in-place sign goes
        // through a sibling temp file and is moved back over the original.
        boolean inPlace = output == null;
        File target = inPlace ? new File(input.getAbsolutePath() + ".signing.tmp") : output;

        Integer minSdk = a.getInt("--min-sdk-version");
        try {
            build(signer, input, target, minSdk, a).sign();
        } catch (Exception e) {
            if (minSdk != null || !isMinSdkDetectionFailure(e)) {
                throw e;
            }
            // Some templates omit minSdkVersion from the manifest; assume the
            // oldest release Godot itself supports.
            System.err.println("apksigner: could not read minSdkVersion, assuming " + FALLBACK_MIN_SDK);
            build(signer, input, target, FALLBACK_MIN_SDK, a).sign();
        }

        if (inPlace) {
            Files.move(target.toPath(), input.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
        if (a.verbose) {
            System.out.println("Signed " + (inPlace ? input : output) + " with alias '" + alias + "' (v2)");
        }
        return 0;
    }

    private static ApkSigner build(ApkSigner.SignerConfig signer, File in, File out,
                                   Integer minSdk, Args a) {
        ApkSigner.Builder b = new ApkSigner.Builder(Collections.singletonList(signer))
                .setInputApk(in)
                .setOutputApk(out)
                .setV1SigningEnabled(false)
                .setV2SigningEnabled(a.getBool("--v2-signing-enabled", true))
                .setOtherSignersSignaturesPreserved(false)
                .setCreatedBy("ihig-apksigner");
        if (minSdk != null) {
            b.setMinSdkVersion(minSdk);
        }
        return b.build();
    }

    private static boolean isMinSdkDetectionFailure(Exception e) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t.getClass().getName().contains("MinSdkVersion")) {
                return true;
            }
        }
        return false;
    }

    // --- verify --------------------------------------------------------------

    private static int verify(String[] args) throws Exception {
        Args a = Args.parse(args);
        if (a.positional.isEmpty()) {
            System.err.println("apksigner: no APK given");
            return 1;
        }
        File apk = new File(a.positional.get(0));
        if (!apk.isFile()) {
            System.err.println("apksigner: no such file: " + apk);
            return 1;
        }

        ApkVerifier.Builder b = new ApkVerifier.Builder(apk);
        Integer minSdk = a.getInt("--min-sdk-version");
        if (minSdk != null) {
            b.setMinCheckedPlatformVersion(minSdk);
        }
        ApkVerifier.Result result;
        try {
            result = b.build().verify();
        } catch (Exception e) {
            if (minSdk != null || !isMinSdkDetectionFailure(e)) {
                throw e;
            }
            result = new ApkVerifier.Builder(apk)
                    .setMinCheckedPlatformVersion(FALLBACK_MIN_SDK).build().verify();
        }

        for (ApkVerifier.IssueWithParams w : result.getWarnings()) {
            System.out.println("WARNING: " + w);
        }
        if (!result.isVerified()) {
            for (ApkVerifier.IssueWithParams err : result.getErrors()) {
                System.err.println("ERROR: " + err);
            }
            System.err.println("DOES NOT VERIFY");
            return 1;
        }
        if (a.verbose) {
            System.out.println("Verifies");
            System.out.println("Verified using v1 scheme (JAR signing): " + result.isVerifiedUsingV1Scheme());
            System.out.println("Verified using v2 scheme (APK Signature Scheme v2): " + result.isVerifiedUsingV2Scheme());
            for (X509Certificate c : result.getSignerCertificates()) {
                System.out.println("Signer certificate DN: " + c.getSubjectX500Principal());
            }
        }
        return 0;
    }

    // --- helpers -------------------------------------------------------------

    private static KeyStore loadKeyStore(File file, String explicitType, char[] pass) throws Exception {
        List<String> types = explicitType != null
                ? Collections.singletonList(explicitType)
                : Arrays.asList("PKCS12", "JKS");
        Exception last = null;
        for (String type : types) {
            try (InputStream in = Files.newInputStream(file.toPath())) {
                KeyStore ks = KeyStore.getInstance(type);
                ks.load(in, pass);
                return ks;
            } catch (Exception e) {
                last = e;
            }
        }
        throw new IllegalArgumentException("could not read keystore " + file + ": " + last);
    }

    private static String firstAlias(KeyStore ks) throws Exception {
        Enumeration<String> aliases = ks.aliases();
        while (aliases.hasMoreElements()) {
            String alias = aliases.nextElement();
            if (ks.isKeyEntry(alias)) {
                return alias;
            }
        }
        throw new IllegalArgumentException("keystore contains no key entries");
    }

    /** Understands apksigner's {@code pass:}, {@code env:}, {@code file:} and {@code stdin} forms. */
    private static char[] password(String spec) throws IOException {
        if (spec == null) {
            return new char[0];
        }
        if (spec.startsWith("pass:")) {
            return spec.substring(5).toCharArray();
        }
        if (spec.startsWith("env:")) {
            String v = System.getenv(spec.substring(4));
            if (v == null) {
                throw new IllegalArgumentException("environment variable not set: " + spec.substring(4));
            }
            return v.toCharArray();
        }
        if (spec.startsWith("file:")) {
            Path p = Paths.get(spec.substring(5));
            return new String(Files.readAllBytes(p), StandardCharsets.UTF_8).trim().toCharArray();
        }
        if (spec.equals("stdin")) {
            byte[] all = readAll(System.in);
            return new String(all, StandardCharsets.UTF_8).trim().toCharArray();
        }
        return spec.toCharArray();
    }

    private static byte[] readAll(InputStream in) throws IOException {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }

    /** Minimal apksigner-compatible argument parser. */
    private static final class Args {
        final List<String> positional = new ArrayList<>();
        final java.util.Map<String, String> flags = new java.util.HashMap<>();
        boolean verbose;

        static Args parse(String[] argv) {
            Args a = new Args();
            // argv[0] is the sub-command.
            for (int i = 1; i < argv.length; i++) {
                String arg = argv[i];
                if (arg.equals("--verbose") || arg.equals("-v")) {
                    a.verbose = true;
                } else if (BARE_FLAGS.contains(arg)) {
                    a.flags.put(arg, "true");
                } else if (VALUE_FLAGS.contains(arg)) {
                    if (i + 1 >= argv.length) {
                        throw new IllegalArgumentException("missing value for " + arg);
                    }
                    a.flags.put(arg, argv[++i]);
                } else if (arg.startsWith("-")) {
                    throw new IllegalArgumentException("unsupported option: " + arg);
                } else {
                    a.positional.add(arg);
                }
            }
            return a;
        }

        String get(String flag) {
            return flags.get(flag);
        }

        Integer getInt(String flag) {
            String v = flags.get(flag);
            return v == null ? null : Integer.valueOf(v.trim());
        }

        boolean getBool(String flag, boolean fallback) {
            String v = flags.get(flag);
            return v == null ? fallback : Boolean.parseBoolean(v.trim());
        }
    }

    private ApkSignerCli() {
    }
}
