-- 项目：olist 电商经营分析项目
-- 文件：14_payment_type_analysis.sql
-- 作用：提取支付方式分析数据

select
    p.payment_type as '支付方式',
    count(distinct p.order_id) as '订单量',
    round(sum(p.payment_value), 2) as '成交总额',
    round(sum(p.payment_value) / count(distinct p.order_id), 2) as '客单价'
from olist_order_payments_dataset p
         join olist_orders_dataset o
              on p.order_id = o.order_id
where o.order_status = 'delivered'
group by p.payment_type
order by round(sum(p.payment_value), 2) desc;
