import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Enumeration;
import java.util.UUID;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.jar.JarInputStream;
import java.util.jar.JarOutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Properties;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Constructor;
import java.net.MalformedURLException;
import java.lang.ClassNotFoundException;
import java.lang.NoSuchMethodException;
import java.lang.IllegalAccessException;
import java.lang.InstantiationException;
import java.util.Map;
import java.util.HashMap;
import java.lang.reflect.Field;
import java.io.FileWriter;
import java.security.CodeSource;
import java.security.ProtectionDomain;

class JarMain {

    // declare as class variable to be used in addShutdownHook
    private static URLClassLoader classLoader = null;

    // executed by java -jar <jar file name>
    public static void main(String[] args) {
        debug("Start java process in jar file "+jar_file_name());
        debug("JVM: "+System.getProperty("java.vm.vendor")+" "+System.getProperty("java.vm.name")+" "+System.getProperty("java.vm.version")+" "+System.getProperty("java.home"));
        if (args.length > 0) {
            debug("Java command line arguments are: ");
            for (String arg : args) {
                debug(" - " + arg);
            }
        }

        // create a new folder in temp directory
        File newFolder = new File(System.getProperty("java.io.tmpdir") + File.separator + UUID.randomUUID().toString());
        newFolder.mkdir();

        try {

            // Ensure that environment does not inject external dependencies
            checkEnvForToxicEntries();

            // Get the path of the jar file with valid characters for spaces etc., especially for Windows
            URL jarPathUrl = JarMain.class.getProtectionDomain().getCodeSource().getLocation();

            // Convert the URL to a URI, then to a File
            File jarFile = new File(jarPathUrl.toURI());

            // Get the absolute path of the file
            String jarPath = jarFile.getAbsolutePath();

            // extract the jarFile by unzipping it (not using the jar utility which may not be available)
            System.out.println("Extracting files from "+jarPath+" to "+ newFolder.getAbsolutePath());
            unzip(jarPath, newFolder.getAbsolutePath());

            String app_root = newFolder.getAbsolutePath()+File.separator+"app_root";

            // get the file name of the jruby jar file in newFolder
            File[] files = newFolder.listFiles();
            // get the existing file from files where prefix is jruby-core* and suffix is .jar
            File jrubyCoreFile = null;
            File jrubyStdlibFile = null;
            for (File file : files) {
                if (file.getName().startsWith("jruby-core") && file.getName().endsWith(".jar")) {
                    jrubyCoreFile = file;
                }
                if (file.getName().startsWith("jruby-stdlib") && file.getName().endsWith(".jar")) {
                    jrubyStdlibFile = file;
                }
            }
            debug("jruby core jar file is  : "+ jrubyCoreFile.getAbsolutePath());
            debug("jruby stdlib jar file is: "+ jrubyStdlibFile.getAbsolutePath());

            // read the property file and get the port number
            String executable = "Executable definition missing";    // Default if nothing else is specified
            String executable_params = "";

            Properties prop = new Properties();
            prop.load(new FileInputStream(newFolder.getAbsolutePath()+File.separator+"jarbler.properties"));
            executable          = prop.getProperty("jarbler.executable");
            executable_params   = prop.getProperty("jarbler.executable_params");
            String gem_home_suffix     = prop.getProperty("jarbler.gem_home_suffix");

            Boolean compile_ruby_files = Boolean.parseBoolean(prop.getProperty("jarbler.compile_ruby_files", "false"));
            if (compile_ruby_files) {
              debug("Set system property jruby.aot.loadClasses = true");
              // ensure that .class files are loaded at require time if rb files are not present
              System.setProperty("jruby.aot.loadClasses", "true");
            }

            // throw exception if executable is null
            if (executable == null) {
                throw new RuntimeException("Property 'executable' definition missing in jarbler.properties");
            }

            // single path to the gems directory
            String gem_home = newFolder.getAbsolutePath()+File.separator+"gems";

            // create the bundle config file with the path of the gems
            create_bundle_config(app_root, gem_home);

            // Load the Jar file
            classLoader = new URLClassLoader(new URL[]{
                jrubyCoreFile.toURI().toURL(),
                jrubyStdlibFile.toURI().toURL()
                //new URL("file:/" + jrubyCoreFile.getAbsolutePath()),
                //new URL("file:/" + jrubyStdlibFile.getAbsolutePath())
            });
            // Load the class
            Class<?> clazz = classLoader.loadClass("org.jruby.Main");

            // Get the method
            Method mainMethod = clazz.getMethod("main", String[].class);

            // Create an instance of the class
            Constructor<?> constructor = clazz.getConstructor();
            Object instance = (Object) constructor.newInstance();
            //Object instance = clazz.newInstance();

            // Prepare the argument list
            ArrayList<String> mainArgs = new ArrayList<String>();
            mainArgs.add(executable);
            if (executable_params != null) {
                for (String param : executable_params.split(" ")) {
                    mainArgs.add(param);
                }
            }
            // add possible command line arguments
            if (args.length > 0) {
                for (String arg : args) {
                    mainArgs.add(arg);
                }
            }

            debug("JRuby set property 'user.dir' to '" + app_root + "'");
            System.setProperty("user.dir", app_root);

            // GEM_HOME not explicitely set because this is done by Bundle.setup based on the .bundle/config file
            // Setting GEM_HOME explicitely may cause problems with the JRuby runtime (Gem::GemNotFoundException: can't find gem bundler (= 2.6.3) with executable bundle)
            //String full_gem_home = gem_home + File.separator + gem_home_suffix.replace("/", File.separator);
            //debug("JRuby set property 'jruby.gem.home' to '" + full_gem_home + "'");
            //System.setProperty("jruby.gem.home", full_gem_home);

            debug("JRuby program starts with the following arguments: ");
            for (String arg : mainArgs) {
                debug(" - " + arg);
            }

            // Add code to execute at System.exit
            // ensure cleanup of the temporary directory also at hard exit in Ruby code like 'exit' or 'System.exit'
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                debug("Execute shutdown hook");
                try {
                    if (classLoader != null) {
                        // Free the JRuby jars to allow deletion of the temporary directory
                        classLoader.close();
                        classLoader = null; // Remove reference
                        System.gc(); // Suggest garbage collection
                    }
                    // remove the temp directory newFolder if not DEBUG mode
                    if (debug_active()) {
                        System.out.println("DEBUG mode is active, temporary folder is not removed at process termination: "+ newFolder.getAbsolutePath());
                    } else {
                        deleteFolder(newFolder);
                    }
                } catch (Exception e) {
                    System.err.println("Exception in shutdown hook: "+ e.getMessage());
                    e.printStackTrace();
                }
            }));

            // call the method org.jruby.Main.main
            debug("Calling org.jruby.Main.main with: "+ mainArgs);
            mainMethod.invoke(null, (Object)mainArgs.toArray(new String[mainArgs.size()]));
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1); // signal unsuccessful termination
        } finally {
            // Called only if the JVM is not terminated by System.exit before, see addShutdownHook
            // This code is not executed if called 'exit' or 'System.exit' in Ruby code before
            debug("Applicaton finished in finalize block");
        }
    }

    private static void unzip(String fileZip, String destination) throws IOException {
        File destDir = new File(destination);

        byte[] buffer = new byte[1024];
        ZipInputStream zis = new ZipInputStream(new FileInputStream(fileZip));
        ZipEntry zipEntry = zis.getNextEntry();
        while (zipEntry != null) {
            while (zipEntry != null) {
                File newFile = newFile(destDir, zipEntry);
                if (zipEntry.isDirectory()) {
                    if (!newFile.isDirectory() && !newFile.mkdirs()) {
                        throw new IOException("Failed to create directory " + newFile);
                    }
                } else {
                    // fix for Windows-created archives
                    File parent = newFile.getParentFile();
                    if (!parent.isDirectory() && !parent.mkdirs()) {
                        throw new IOException("Failed to create directory " + parent);
                    }

                    // write file content
                    FileOutputStream fos = new FileOutputStream(newFile);
                    int len;
                    while ((len = zis.read(buffer)) > 0) {
                        fos.write(buffer, 0, len);
                    }
                    fos.close();
                }
                zipEntry = zis.getNextEntry();
            }
        }

        zis.closeEntry();
        zis.close();
    }

    /**
     * Create a new file with the given parent and name.
     *
     * @param destinationDir The parent directory.
     * @param zipEntry The zip entry with name of the new file.
     * @return The new File.
     * @throws IOException If an I/O error occurs.
     */
    private static File newFile(File destinationDir, ZipEntry zipEntry) throws IOException {
    try {
        String destFileName = zipEntry.getName();

        // the platform name in extension dir depends on the the target java version, therfore we replace the platform name here
        if (destFileName.contains("universal-java-XX")) {
            String newPlatformName = "universal-java-" + javaMajorRelease4RubyPlatform();
            debug ("Replacing platform name in file '" + destFileName + "' from 'universal-java-XX' to '" + newPlatformName + "'");
            destFileName = destFileName.replace("universal-java-XX", newPlatformName);
        }

        File destFile = new File(destinationDir, destFileName);

        String destDirPath = destinationDir.getCanonicalPath();
        String destFilePath = destFile.getCanonicalPath();

        if (!destFilePath.startsWith(destDirPath + File.separator)) {
            throw new IOException("Entry is outside of the target dir: " + zipEntry.getName());
        }

        return destFile;
    } catch (IOException exception) {
        System.out.println("JarMain.newFile: Error '"+ exception.getMessage() + "' while creating new file: '" + zipEntry.getName() + "' in dir '" + destinationDir.getName() + "'");
        System.out.println("Full target dir name is: " + destinationDir.getCanonicalPath());
        // Rethrow the exception
        throw exception;
        }

    }

    private static boolean debug_active() {
        String debug = System.getenv("DEBUG");
        return debug != null && debug.toUpperCase().equals("TRUE");
    }

    private static void debug(String msg) {
        if (debug_active()) {
            System.err.println(msg);
        }
    }

    private static void deleteFolder(File file) {
        try
        {
            if (file.isDirectory()) {
               File[] entries = file.listFiles();
               for (File currentFile: entries) {
                   deleteFolder(currentFile);
               }
            }
            file.delete();
        } catch(Throwable t) {
            System.err.println("Could not DELETE file: " + file.getAbsolutePath() + " - " + t.getMessage());
        }
    }

    private static void create_bundle_config(String app_root, String gem_path) throws IOException {
        File bundle_config = new File(app_root + File.separator + ".bundle");
        bundle_config.mkdir();
        File bundle_config_file = new File(bundle_config.getAbsolutePath() + File.separator + "config");
        bundle_config_file.createNewFile();
        FileWriter fw = new FileWriter(bundle_config_file);
        fw.write("---\n");
        fw.write("BUNDLE_PATH: " + gem_path + "\n");
        fw.write("BUNDLE_WITHOUT: test:development\n");
        fw.close();
    }

    private static String jar_file_name() {
        String jarFileName = "";

        try {
            ProtectionDomain protectionDomain = JarMain.class.getProtectionDomain();
            CodeSource codeSource = protectionDomain.getCodeSource();
            URL location = codeSource.getLocation();
            jarFileName = new File(location.toURI()).getName();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return jarFileName;
    }

    /**
     * Check environment for entries that may inluence execution of Ruby code.
     * @param errorSummary The current error summary
     */
    private static void checkEnvForToxicEntries(){
        StringBuilder errorSummary = new StringBuilder("");
        String toxicEntries[] = {
            "BUNDLE_BIN_PATH",
            "BUNDLE_GEMFILE",
            "BUNDLER_SETUP",
            "BUNDLER_VERSION",
            "GEM_HOME",
            "GEM_PATH",
            "RUBYLIB",
            "RUBYOPT",
            "RUBYPATH",
            "RUBYSHELL"
        };

        Arrays.stream(toxicEntries).forEach(entry -> {
            String envVal = System.getenv(entry);
            if (envVal != null) {
                errorSummary.append("Found environment variable '"+entry+"' with value '"+envVal+"'\n");
                debug("Possibly toxic environment variable found: '"+entry+"'! Remove it from environment before execution of jar file if it causes errors.");
            }
        });

        if (!errorSummary.toString().isEmpty()){
            System.err.println("The follwing environment variables may influence the execution of the packaged Ruby code.");
            System.err.println("Please remove this environment entries before the execution of the jar file if they cause errors.");
            System.err.println(errorSummary);
        }
    }

    /**
     * Get the major release of the Java platform a'la universal-java-XX
     * @return [int] The major release of the Java platform, e.g. "java-universal-11"
     */

    private static int javaMajorRelease4RubyPlatform() {
        try {
            // --- Ansatz 1: Für Java 9 und höher (empfohlen) ---
            // Versuche, Runtime.version() zu verwenden.
            // Wir nutzen Reflection, damit der Code auch mit einem Java 8 JDK kompiliert werden kann,
            // aber trotzdem die moderne API verwendet, wenn er auf einem Java 9+ JRE läuft.
            Class<?> runtimeClass = Class.forName("java.lang.Runtime");
            Method versionMethod = runtimeClass.getMethod("version");
            Object versionObject = versionMethod.invoke(null); // Runtime.version() ist eine statische Methode

            // Hole die "major" Methode vom zurückgegebenen Runtime.Version Objekt
            Class<?> versionClass = Class.forName("java.lang.Runtime$Version");
            Method majorMethod = versionClass.getMethod("major");
            return (int) majorMethod.invoke(versionObject);

        } catch (ClassNotFoundException | NoSuchMethodException | IllegalAccessException | java.lang.reflect.InvocationTargetException e) {
            // --- Ansatz 2: Fallback für Java 8 und älter ---
            // Dieser Block wird ausgeführt, wenn Runtime.version() nicht verfügbar ist
            // (z.B. auf Java 8) oder wenn Reflection fehlschlägt.

            String javaVersion = System.getProperty("java.version");
            // Beispiele für java.version:
            // Java 8: "1.8.0_291"
            // Java 11: "11.0.11"
            // Java 17: "17.0.2"
            // Java 9: "9" (manchmal ohne weitere Punkte)

            // Prüfe, ob es sich um das alte "1.x.y" Format handelt
            if (javaVersion.startsWith("1.")) {
                // Für "1.x.y_z" ist die Hauptversion 'x'
                // Beispiel: "1.8.0_291" -> '8'
                try {
                    return Integer.parseInt(javaVersion.substring(2, 3));
                } catch (NumberFormatException ex) {
                    // Sollte nicht passieren, aber zur Sicherheit
                    System.err.println("Fehler beim Parsen der Java 1.x Version: " + javaVersion + " - " + ex.getMessage());
                    return -1;
                }
            } else {
                // Für "x.y.z" oder "x" Format (Java 9+ Stil)
                // Beispiel: "11.0.11" -> '11', "17.0.2" -> '17', "9" -> '9'
                int dotIndex = javaVersion.indexOf('.');
                if (dotIndex != -1) {
                    try {
                        return Integer.parseInt(javaVersion.substring(0, dotIndex));
                    } catch (NumberFormatException ex) {
                        System.err.println("Fehler beim Parsen der Java x.y Version: " + javaVersion + " - " + ex.getMessage());
                        return -1;
                    }
                } else {
                    // Fallback für den Fall, dass nur die Hauptversion angegeben ist (z.B. "9", "10", "11")
                    try {
                        return Integer.parseInt(javaVersion);
                    } catch (NumberFormatException ex) {
                        System.err.println("Fehler beim Parsen der Java Hauptversion: " + javaVersion + " - " + ex.getMessage());
                        return -1;
                    }
                }
            }
        } catch (NumberFormatException e) {
            // Dieser Catch-Block fängt Fehler ab, die auftreten, wenn System.getProperty("java.version")
            // ein unerwartetes Format hat, das nicht geparst werden kann.
            System.err.println("Fehler beim Parsen der Java-Versionszeichenkette: " + System.getProperty("java.version") + " - " + e.getMessage());
            return -1;
        }
    }
}