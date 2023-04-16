# Steps for creating gem
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

gem install jarbler-0.1.0.gem
if [ $? -ne 0 ]; then
  echo "Gem install failed."
  exit 1
fi
