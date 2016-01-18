-- 18.01.2016 l3talka
CREATE DATABASE `ccwv2` /*!40100 DEFAULT CHARACTER SET utf8 */

CREATE TABLE `devices` (
 `id` int(11) NOT NULL AUTO_INCREMENT,
 `device` varchar(255) NOT NULL,
 `created` int(11) NOT NULL,
 `updated` int(11) NOT NULL,
 PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


ALTER TABLE `devices` ADD `status` INT(1) NOT NULL COMMENT '0 = offline 1 = online';