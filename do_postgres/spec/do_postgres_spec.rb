require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

#
#
# Create a postgres db named do_test that accepts connections 
# from localhost from your current user (without password) to enable this spec.
#
# You also need to allow passwordless access from localhost-
# locate the following line in your pg_hba.conf file:
#
#  # IPv4 local connections:
#  host    all         all         127.0.0.1/32          md5
#
# and replace 'md5' with 'trust' for these specs to work
#
#

def ensure_users_table_and_return_connection
  connection = DataObjects::Connection.new("postgres://localhost/do_test")
  connection.create_command("DROP TABLE users").execute_non_query rescue nil
  connection.create_command(<<EOF
 CREATE TABLE users
 (
   id serial NOT NULL,
   "name" text,
   registered boolean DEFAULT false,
   money double precision DEFAULT 1908.56,
   created_on date DEFAULT ('now'::text)::date,
   created_at timestamp without time zone DEFAULT now(),
   born_at time without time zone DEFAULT now()
 )
 WITH (OIDS=FALSE);
EOF
).execute_non_query
  return connection
end

describe "DataObjects::Postgres::Connection" do
  it "should connect to the db" do
    connection = DataObjects::Connection.new("postgres://localhost/do_test")
  end
end

describe "DataObjects::Postgres::Command" do
  before :all do
    @connection = ensure_users_table_and_return_connection
  end
  
  it "should create a command" do
    @connection.create_command("CREATE TABLE users").should be_a_kind_of(DataObjects::Postgres::Command)
  end
  
  it "should set types" do
    command = @connection.create_command("SELECT id, name FROM users")
    command.set_types [Integer, String]
    command.instance_variable_get("@field_types").should == [Integer, String]
  end
  
  it "should execute a non query" do
    command = @connection.create_command("INSERT INTO users (name) VALUES ('Test')")
    result = command.execute_non_query
    result.should be_a_kind_of(DataObjects::Postgres::Result)
  end

  it "should execute a reader" do
    command = @connection.create_command("SELECT * FROM users")
    reader = command.execute_reader
    reader.should be_a_kind_of(DataObjects::Postgres::Reader)
    reader.close.should == true
  end
end

describe "DataObjects::Postgres::Result" do
  before :all do
    @connection = ensure_users_table_and_return_connection
  end

  it "should raise errors on bad queries" do
    command = @connection.create_command("INSER INTO users (name) VALUES ('Test')")
    lambda { command.execute_non_query }.should raise_error
    command = @connection.create_command("INSERT INTO users (non_existant_field) VALUES ('Test')")
    lambda { command.execute_non_query }.should raise_error
  end
  
  it "should not have an insert_id without RETURNING" do    
    command = @connection.create_command("INSERT INTO users (name) VALUES ('Test')")
    result = command.execute_non_query
    result.insert_id.should == 0;
    result.to_i.should == 1;
  end
  
  it "should have an insert_id when RETURNING" do
    command = @connection.create_command("INSERT INTO users (name) VALUES ('Test') RETURNING id")
    result = command.execute_non_query
    result.insert_id.should_not == 0;
    result.to_i.should == 1;
  end
end

describe "DataObjects::Postgres::Reader" do
  before :all do
    @connection = ensure_users_table_and_return_connection
    @connection.create_command("INSERT INTO users (name) VALUES ('Test')").execute_non_query
    @connection.create_command("INSERT INTO users (name) VALUES ('Test')").execute_non_query
    @connection.create_command("INSERT INTO users (name) VALUES ('Test')").execute_non_query
  end
  
  it "should raise errors on bad queries" do
    command = @connection.create_command("SELT * FROM users")
    lambda { command.execute_reader }.should raise_error
    command = @connection.create_command("SELECT * FROM non_existant_table")
    lambda { command.execute_reader }.should raise_error
  end
  
  it "should open and close a reader" do
    command = @connection.create_command("SELECT * FROM users LIMIT 3")
    command.set_types [Integer, String]
    reader = command.execute_reader
    reader.close
  end
  
  it "should typecast a value from the postgres type" do
    command = @connection.create_command("SELECT id, name, registered, money FROM users ORDER BY id DESC LIMIT 3")
    reader = command.execute_reader
    reader.send(:instance_variable_get, "@field_count").should == 4
    reader.send(:instance_variable_get, "@row_count").should == 3
    while ( reader.next!)
      reader.values[0].should be_a_kind_of(Integer)
      reader.values[1].should be_a_kind_of(String)
      reader.values[2].should == false
      reader.values[3].should == 1908.56
    end
    reader.close
  end
  
  it "should typecast from set_types" do
    command = @connection.create_command("SELECT id, name FROM users ORDER BY id LIMIT 1")
    command.set_types [Fixnum, String]
    reader = command.execute_reader
    reader.next!
    reader.values[0].should be_a_kind_of(Fixnum)
    reader.values[1].should be_a_kind_of(String)
    reader.close
  end
  
  it "should handle a null value" do
    @connection.create_command("INSERT INTO users (name) VALUES (NULL)").execute_non_query
    command = @connection.create_command("SELECT name from users WHERE name is null")
    reader = command.execute_reader
    reader.next!
    reader.values[0].should == nil
  end
  
  it "should typecast a date field" do
    command = @connection.create_command("SELECT created_on FROM users WHERE created_on is not null LIMIT 1")
    reader = command.execute_reader
    reader.next!
    reader.values[0].should be_a_kind_of(Date)
  end
  
  it "should typecast a timestamp field" do
    command = @connection.create_command("SELECT created_at FROM users WHERE created_at is not null LIMIT 1")
    reader = command.execute_reader
    reader.next!
    dt = reader.values[0]
    p [dt, dt.year]
    reader.values[0].should be_a_kind_of(DateTime)
  end
  
  it "should typecast a time field" do
    command = @connection.create_command("SELECT born_at FROM users LIMIT 1")
    reader = command.execute_reader
    reader.next!
    reader.values[0].should be_a_kind_of(Time)
  end
end





















