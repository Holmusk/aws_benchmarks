UPDATE bench SET time_taken = ROUND(EXTRACT(milliseconds FROM message - upload));

with time_taken_t as (
    select min(time_taken) as min,
           max(time_taken) as max
      from bench
),
     histogram as (
   select width_bucket((time_taken), min, max, 15) as bucket,
          int4range(min(time_taken), max(time_taken), '[]') as range,
          count(*) as freq
     from bench, time_taken_t
 group by bucket
 order by bucket
)
 select bucket, range, freq,
        repeat('■',
               (   freq::float
                 / max(freq) over()
                 * 30
               )::int
        ) as bar
   from histogram;