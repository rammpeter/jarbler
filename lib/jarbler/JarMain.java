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
            URLClassLoader classLoader = new URLClassLoader(new URL[]{
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

            String full_gem_home = gem_home + File.separator + gem_home_suffix.replace("/", File.separator);
            debug("JRuby set property 'jruby.gem.home' to '" + full_gem_home + "'");
            System.setProperty("jruby.gem.home", full_gem_home);

            String full_gem_path = full_gem_home +  File.pathSeparator + full_gem_home + File.separator + "bundler" ;
            debug("JRuby set property 'jruby.gem.path' to '" + full_gem_path + "'");
            System.setProperty("jruby.gem.path", full_gem_path);

            debug("JRuby program starts with the following arguments: ");
            for (String arg : mainArgs) {
                debug(" - " + arg);
            }

            // call the method org.jruby.Main.main
            debug("Calling org.jruby.Main.main with: "+ mainArgs);
            mainMethod.invoke(null, (Object)mainArgs.toArray(new String[mainArgs.size()]));
            // TODO: evaluate return value
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            // remove the temp directory newFolder if not DEBUG mode
            if (System.getenv("DEBUG") != null) {
                System.out.println("DEBUG mode is active, temporary folder is not removed at process termination: "+ newFolder.getAbsolutePath());
            } else {
                deleteFolder(newFolder);
            }
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
        File destFile = new File(destinationDir, zipEntry.getName());

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

    private static void debug(String msg) {
        if (System.getenv("DEBUG") != null) {
            System.out.println(msg);
        }
    }

   private static void deleteFolder(File file){
      for (File subFile : file.listFiles()) {
         if(subFile.isDirectory()) {
            deleteFolder(subFile);
         } else {
            subFile.delete();
         }
      }
      file.delete();
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
}