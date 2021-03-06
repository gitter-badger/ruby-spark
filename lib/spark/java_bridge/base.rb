##
# Spark::JavaBridge::Base
#
# Parent for all adapter (ruby - java)
#
module Spark
  module JavaBridge
    class Base

      include Spark::Helper::System

      JAVA_OBJECTS = [
        'java.util.ArrayList',
        'org.apache.spark.SparkConf',
        'org.apache.spark.api.java.JavaSparkContext',
        'org.apache.spark.api.ruby.RubyRDD',
        'org.apache.spark.api.ruby.RubyUtils',
        'org.apache.spark.api.ruby.RubyWorker',
        'org.apache.spark.api.ruby.PairwiseRDD',
        'org.apache.spark.api.ruby.RubyAccumulatorParam',
        'org.apache.spark.api.ruby.RubySerializer',
        'org.apache.spark.api.python.PythonRDD',
        'org.apache.spark.api.python.PythonPartitioner',
        'org.apache.spark.ui.ruby.RubyTab',
        'org.apache.spark.mllib.api.ruby.RubyMLLibAPI',
        'scala.collection.mutable.HashMap',
        :JInteger  => 'java.lang.Integer',
        :JLong     => 'java.lang.Long',
        :JLogger   => 'org.apache.log4j.Logger',
        :JLevel    => 'org.apache.log4j.Level',
        :JPriority => 'org.apache.log4j.Priority',
        :JUtils    => 'org.apache.spark.util.Utils',
        :JStorageLevel => 'org.apache.spark.storage.StorageLevel',
        :JDenseVector => 'org.apache.spark.mllib.linalg.DenseVector',
        :JDenseMatrix => 'org.apache.spark.mllib.linalg.DenseMatrix'
      ]

      JAVA_TEST_OBJECTS = [
        'org.apache.spark.mllib.api.ruby.RubyMLLibUtilAPI'
      ]

      RUBY_TO_JAVA_SKIP = [Fixnum, Integer]

      def initialize(spark_home)
        @spark_home = spark_home
      end

      # Import all important classes into Objects
      def load
        return if @loaded

        java_objects.each do |name, klass|
          import(name, klass)
        end

        @loaded = true
        nil
      end

      # Import classes for testing
      def load_test
        return if @loaded_test

        java_test_objects.each do |name, klass|
          import(name, klass)
        end

        @loaded_test = true
        nil
      end

      # Call java object
      def call(klass, method, *args)
        # To java
        args.map!{|item| to_java(item)}

        # Call java
        result = klass.__send__(method, *args)

        # To ruby
        to_ruby(result)
      end

      def to_java_array_list(array)
        array_list = ArrayList.new
        array.each do |item|
          array_list.add(to_java(item))
        end
        array_list
      end

      def to_long(number)
        return nil if number.nil?
        JLong.new(number)
      end

      def to_java(object)
        if RUBY_TO_JAVA_SKIP.include?(object.class)
          # Some object are convert automatically
          # This is for preventing errors
          # For example: jruby store integer as long so 1.to_java is Long
          object
        elsif object.respond_to?(:to_java)
          object.to_java
        elsif object.is_a?(Array)
          to_java_array_list(object)
        else
          object
        end
      end

      # Array problem:
      #   Rjb:   object.toArray -> Array
      #   Jruby: object.toArray -> java.lang.Object
      #
      def to_ruby(object)
        if java_object?(object)
          class_name = object.getClass.getSimpleName
          case class_name
          when 'ArraySeq'
            result = []
            iterator = object.iterator
            while iterator.hasNext
              result << to_ruby(iterator.next)
            end
            result
          when 'Map2', 'Map3', 'Map4', 'HashTrieMap'
            Hash[
              object.toSeq.array.to_a.map!{|item| [item._1, item._2]}
            ]
          when 'SeqWrapper'; object.toArray.to_a.map!{|item| to_ruby(item)}
          when 'ofRef';      object.array.to_a.map!{|item| to_ruby(item)} # WrappedArray$ofRef
          when 'LabeledPoint'; Spark::Mllib::LabeledPoint.from_java(object)
          when 'DenseVector';  Spark::Mllib::DenseVector.from_java(object)
          when 'KMeansModel';  Spark::Mllib::KMeansModel.from_java(object)
          when 'DenseMatrix';  Spark::Mllib::DenseMatrix.from_java(object)
          else
            # Some RDD
            if class_name != 'JavaRDD' && class_name.end_with?('RDD')
              object = object.toJavaRDD
              class_name = 'JavaRDD'
            end

            # JavaRDD
            if class_name == 'JavaRDD'
              jrdd = RubyRDD.toRuby(object)

              serializer = Spark::Serializer.build { __batched__(__marshal__) }
              serializer = Spark::Serializer.build { __batched__(__marshal__, 2) }

              return Spark::RDD.new(jrdd, Spark.sc, serializer, deserializer)
            end

            # Unknow
            Spark.logger.warn("Java object '#{object.getClass.name}' was not converted.")
            object
          end

        else
          # Already transfered
          object
        end
      end

      alias_method :java_to_ruby, :to_ruby
      alias_method :ruby_to_java, :to_java

      private

        def jars
          result = []
          if File.file?(@spark_home)
            result << @spark_home
          else
            result << Dir.glob(File.join(@spark_home, '*.jar'))
          end
          result.flatten
        end

        def objects_with_names(objects)
          hash = {}
          objects.each do |object|
            if object.is_a?(Hash)
              hash.merge!(object)
            else
              key = object.split('.').last.to_sym
              hash[key] = object
            end
          end
          hash
        end

        def java_objects
          objects_with_names(JAVA_OBJECTS)
        end

        def java_test_objects
          objects_with_names(JAVA_TEST_OBJECTS)
        end

    end
  end
end
