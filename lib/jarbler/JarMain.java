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
    // No arguments are passed
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
            // Get the path of the jar file
            String jarPath = JarMain.class.getProtectionDomain().getCodeSource().getLocation().getPath();

            // remove the leading slash if path is a windows path
            String os = System.getProperty("os.name").toLowerCase();
            boolean isWindows = os.contains("windows");
            if (os.contains("windows") && jarPath.startsWith("/") && jarPath.indexOf(':') != -1) {
                jarPath = jarPath.substring(1); // remove the leading slash
            }

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
            executable = prop.getProperty("jarbler.executable");
            executable_params = prop.getProperty("jarbler.executable_params");

            // throw exception if executable is null
            if (executable == null) {
                throw new RuntimeException("Property 'executable' definition missing in jarbler.properties");
            }

            // create the bundle config file with the path of the gems
            create_bundle_config(app_root, newFolder.getAbsolutePath()+File.separator+"gems");

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

            debug("jRuby program starts with the following arguments: ");
            for (String arg : mainArgs) {
                debug(" - " + arg);
            }

            debug("jRuby set property 'user.dir' to '" + app_root + "'");
            System.setProperty("user.dir", app_root);
            // call the method org.jruby.Main.main
            debug("Calling org.jruby.Main.main with: "+ mainArgs);
            mainMethod.invoke(null, (Object)mainArgs.toArray(new String[mainArgs.size()]));
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

    private static File newFile(File destinationDir, ZipEntry zipEntry) throws IOException {
        File destFile = new File(destinationDir, zipEntry.getName());

        String destDirPath = destinationDir.getCanonicalPath();
        String destFilePath = destFile.getCanonicalPath();

        if (!destFilePath.startsWith(destDirPath + File.separator)) {
            throw new IOException("Entry is outside of the target dir: " + zipEntry.getName());
        }

        return destFile;
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
}