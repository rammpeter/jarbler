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

class JarMain {
   static void deleteFolder(File file){
      for (File subFile : file.listFiles()) {
         if(subFile.isDirectory()) {
            deleteFolder(subFile);
         } else {
            subFile.delete();
         }
      }
      file.delete();
    }

    // executed by java -jar <jar file name>
    // No arguments are passed
    public static void main(String[] args) {
        System.out.println("Start java process in jar file");
        if (args.length > 0) {
            System.out.println("Arguments are: ");
            for (String arg : args) {
                System.out.println(arg);
            }
        }
        // create a new folder in temp directory
        File newFolder = new File(System.getProperty("java.io.tmpdir") + File.separator + UUID.randomUUID().toString());
        newFolder.mkdir();
        // Get the path of the jar file
        String jarPath = JarMain.class.getProtectionDomain().getCodeSource().getLocation().getPath();

        // remove the leading slash if path is a windows path
        String os = System.getProperty("os.name").toLowerCase();
        boolean isWindows = os.contains("windows");
        if (os.contains("windows") && jarPath.startsWith("/") && jarPath.indexOf(':') != -1) {
            jarPath = jarPath.substring(1); // remove the leading slash
        }

        // extract the jarFile by executing jar -xf jarFileName

        try {
            System.out.println("Extracting files from "+jarPath+" to "+ newFolder.getAbsolutePath());
            unzip(jarPath, newFolder.getAbsolutePath());
        } catch (IOException e) {
            e.printStackTrace();
        }


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
        System.out.println("jruby core jar file is  : "+ jrubyCoreFile.getAbsolutePath());
        System.out.println("jruby stdlib jar file is: "+ jrubyStdlibFile.getAbsolutePath());

        ArrayList<String> classpaths = new ArrayList<String>();
        classpaths.add(jrubyCoreFile.getAbsolutePath());
        classpaths.add(jrubyStdlibFile.getAbsolutePath());
        String classpath = String.join(File.pathSeparator, classpaths);

        // read the property file and get the port number
        String portNumber = "8080";
        try {
            Properties prop = new Properties();
            prop.load(new FileInputStream(newFolder.getAbsolutePath()+File.separator+"jarbler.properties"));
            portNumber = prop.getProperty("jarbler.port");
        } catch (IOException e) {
            e.printStackTrace();
        }

        // TODO: remove files version specific JDBC drivers according to Java version (configured in jarble.rb)

        // execute the jar file
        try {
            ProcessBuilder pb = new ProcessBuilder("java", "-cp", classpath, "org.jruby.Main",  "bin/rails", "server", "-p", portNumber, "-e", "production");
            pb.directory(new File(newFolder.getAbsolutePath()+File.separator+"app_root"));
            java.util.Map<String, String> env = pb.environment();
            env.put("GEM_PATH", newFolder.getAbsolutePath()+File.separator+"gems");
            env.put("GEM_HOME", newFolder.getAbsolutePath()+File.separator+"gems");
            env.put("BUNDLE_PATH", newFolder.getAbsolutePath()+File.separator+"gems");
            env.put("BUNDLE_WITHOUT", "test:development");  // exclude test and development dependencies from Gemfile check
            pb.redirectErrorStream(true);                                       // redirect error stream to output stream
            System.out.println("Executing: " + String.join(" ", pb.command()));
            Process p = pb.start();
            InputStream is = p.getInputStream();
            int i = 0;
            while ((i = is.read()) != -1) {
                System.out.print((char) i);
            }
            is.close();
        } catch (IOException e) {
            e.printStackTrace();
        }


        // remove the temp directory newFolder
        System.out.println("Removing all content in folder "+ newFolder.getAbsolutePath());
        // TODO: remove comment
        //deleteFolder(newFolder);
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

    public static File newFile(File destinationDir, ZipEntry zipEntry) throws IOException {
        File destFile = new File(destinationDir, zipEntry.getName());

        String destDirPath = destinationDir.getCanonicalPath();
        String destFilePath = destFile.getCanonicalPath();

        if (!destFilePath.startsWith(destDirPath + File.separator)) {
            throw new IOException("Entry is outside of the target dir: " + zipEntry.getName());
        }

        return destFile;
    }
}