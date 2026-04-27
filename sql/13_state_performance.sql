-- 项目：olist 电商经营分析项目
-- 文件：13_state_performance.sql
-- 作用：提取州级地区表现分析数据

with payment_agg as (
    select
        order_id,
        sum(payment_value) as payment_value
    from olist_order_payments_dataset
    group by order_id
),

state_trade as (
    select
        c.customer_state,
        round(sum(p.payment_value), 2) as gmv,
        count(distinct o.order_id) as valid_order_cnt,
        round(sum(p.payment_value) / count(distinct o.order_id), 2) as aov
    from olist_orders_dataset o
    join payment_agg p
        on o.order_id = p.order_id
    join olist_customers_dataset c
        on o.customer_id = c.customer_id
    where o.order_status = 'delivered'
    group by c.customer_state
),

state_fail as (
    select
        c.customer_state,
        round(
            sum(o.order_status in ('canceled', 'unavailable')) / count(*) * 100,
            2
        ) as fail_rate_pct
    from olist_orders_dataset o
    join olist_customers_dataset c
        on o.customer_id = c.customer_id
    where o.order_status in ('delivered', 'canceled', 'unavailable')
    group by c.customer_state
),

state_delivery as (
    select
        c.customer_state,
        round(avg(datediff(o.order_delivered_customer_date, o.order_purchase_timestamp)), 2) as avg_delivery_days
    from olist_orders_dataset o
    join olist_customers_dataset c
        on o.customer_id = c.customer_id
    where o.order_status = 'delivered'
      and o.order_delivered_customer_date is not null
      and o.order_purchase_timestamp is not null
    group by c.customer_state
)

select
    t.customer_state as '客户州',
    t.gmv as '成交总额',
    t.valid_order_cnt as '有效订单量',
    t.aov as '客单价',
    f.fail_rate_pct as '终态失败率(%)',
    d.avg_delivery_days as '平均配送天数(天)'
from state_trade t
join state_fail f
    on t.customer_state = f.customer_state
join state_delivery d
    on t.customer_state = d.customer_state
order by t.gmv desc;
