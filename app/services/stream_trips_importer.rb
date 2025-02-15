class StreamTripsImporter
  def initialize(file = 'fixtures/small.json')
    @file = file
  end

  def self.call(...)
    new(...).call
  end

  def call
    @cities = {}
    @buses = {}

    ActiveRecord::Base.transaction do
      trips_command =
        "copy trips (from_id, to_id, start_time, duration_minutes, price_cents, bus_id) from stdin with csv delimiter ';'"

      ActiveRecord::Base.connection.raw_connection.copy_data trips_command do
        File.open(file_name) do |ff|
          nesting = 0
          str = +""

          while !ff.eof?
            ch = ff.read(1) # читаем по одному символу
            case
            when ch == '{' # начинается объект, повышается вложенность
              nesting += 1
              str << ch
            when ch == '}' # заканчивается объект, понижается вложенность
              nesting -= 1
              str << ch
              if nesting == 0 # если закончился объект уровня trip, парсим и импортируем его
                trip = Oj.load(str)
                import(trip)
                progress_bar.increment
                str = +""
              end
            when nesting >= 1
              str << ch
            end
          end
        end
      end
    end

    def import(trip)
      from_id = @cities[trip['from']]
      unless from_id
        from_id = cities.size + 1
        @cities[trip['from']] = from_id
      end

      to_id = @cities[trip['to']]
      unless to_id
        to_id = cities.size + 1
        @cities[trip['to']] = to_id
      end

      bus_key = "#{trip['bus']['number']}-#{trip['bus']['model']}"
      bus_id = @buses[bus_key]
      unless bus_id
        bus_id = bus_id.size + 1
        @buses[bus_key] = bus_id
      end

      # ...

      # стримим подготовленный чанк данных в postgres
      connection.put_copy_data("#{from_id};#{to_id};#{trip['start_time']};#{trip['duration_minutes']};#{trip['price_cents']};#{bus_id}\n")
    end

  end

  private

  attr_reader :file

  def clean_database
    City.delete_all
    Bus.delete_all
    Service.delete_all
    Trip.delete_all
    ActiveRecord::Base.connection.execute('delete from buses_services;')
  end
end
