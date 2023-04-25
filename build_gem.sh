# Steps for creating gem in local environment

# remove existing gem file
rm -f jarbler-*.gem

rake test
if [ $? -ne 0 ]; then
  echo "Tests failed."
  exit 1
fi

gem build
if [ $? -ne 0 ]; then
  echo "Gem build failed."
  exit 1
fi

gem install `ls jarbler-*.gem`
if [ $? -ne 0 ]; then
  echo "Gem install failed."
  exit 1
fi
