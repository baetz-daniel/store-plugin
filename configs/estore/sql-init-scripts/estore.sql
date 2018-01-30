-- phpMyAdmin SQL Dump
-- version 4.2.12deb2+deb8u2
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Erstellungszeit: 01. Mrz 2017 um 17:46
-- Server Version: 5.5.54-0+deb8u1
-- PHP-Version: 5.6.30-0+deb8u1

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Datenbank: `scripter`
--

DELIMITER $$
--
-- Prozeduren
--
DROP PROCEDURE IF EXISTS `procedure_estore_user_item_delete_expired`$$
CREATE DEFINER=`scripter`@`%` PROCEDURE `procedure_estore_user_item_delete_expired`()
    MODIFIES SQL DATA
BEGIN
DELETE eui FROM `estore_user_item` eui 
	JOIN `estore_item` ei 
    ON (ei.`index` = eui.`estore_item_index`) 
WHERE ei.`expire_after` > 0 
AND TIMESTAMPDIFF(SECOND, eui.`acquire_timestamp`, now()) > (ei.`expire_after` * 24 * 60 * 60);
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_banking`
--

DROP TABLE IF EXISTS `estore_banking`;
CREATE TABLE IF NOT EXISTS `estore_banking` (
`index` int(11) NOT NULL,
  `estore_user_index` int(21) NOT NULL,
  `money` int(11) NOT NULL DEFAULT '5000',
  `auto_deposit` int(11) NOT NULL DEFAULT '0',
  `auto_withdraw` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;


-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_category`
--

DROP TABLE IF EXISTS `estore_category`;
CREATE TABLE IF NOT EXISTS `estore_category` (
`index` int(11) NOT NULL,
  `name` varchar(32) NOT NULL,
  `require_plugin` varchar(32) NOT NULL,
  `description` varchar(128) NOT NULL,
  `order` int(11) NOT NULL,
  `flag` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_item`
--

DROP TABLE IF EXISTS `estore_item`;
CREATE TABLE IF NOT EXISTS `estore_item` (
`index` int(11) NOT NULL,
  `name` varchar(32) NOT NULL,
  `description` varchar(128) NOT NULL,
  `price` int(11) NOT NULL,
  `estore_category_index` int(11) NOT NULL,
  `type` varchar(32) NOT NULL,
  `is_buyable_from` int(11) NOT NULL DEFAULT '7',
  `is_tradeable_to` int(11) NOT NULL DEFAULT '7',
  `is_refundable` tinyint(1) NOT NULL DEFAULT '1',
  `team_only` int(11) NOT NULL DEFAULT '0',
  `flags` int(11) NOT NULL DEFAULT '0',
  `data` text NOT NULL,
  `expire_after` int(3) NOT NULL DEFAULT '0'
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_right_group`
--

DROP TABLE IF EXISTS `estore_right_group`;
CREATE TABLE IF NOT EXISTS `estore_right_group` (
`index` int(11) NOT NULL,
  `name` varchar(32) NOT NULL,
  `flag` int(11) NOT NULL
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;

--
-- Daten für Tabelle `estore_right_group`
--

INSERT INTO `estore_right_group` (`index`, `name`, `flag`) VALUES
(0, 'User', 1),
(1, 'VIP', 2),
(2, 'Admin', 4);

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_user`
--

DROP TABLE IF EXISTS `estore_user`;
CREATE TABLE IF NOT EXISTS `estore_user` (
`index` int(11) NOT NULL,
  `steam_id` int(11) NOT NULL,
  `name` varchar(32) NOT NULL,
  `credits` int(11) NOT NULL,
  `estore_right_group_index` int(11) NOT NULL DEFAULT '0',
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;

--
-- Trigger `estore_user`
--
DROP TRIGGER IF EXISTS `estore_user_insert_after`;
DELIMITER //
CREATE TRIGGER `estore_user_insert_after` AFTER INSERT ON `estore_user`
 FOR EACH ROW BEGIN

   INSERT INTO `estore_banking` (`estore_user_index`)
   VALUES (new.index);

END
//
DELIMITER ;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_user_history`
--

DROP TABLE IF EXISTS `estore_user_history`;
CREATE TABLE IF NOT EXISTS `estore_user_history` (
`index` int(11) NOT NULL,
  `estore_user_index` int(11) NOT NULL,
  `date` date NOT NULL,
  `time` time NOT NULL,
  `count` int(11) NOT NULL
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;


-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `estore_user_item`
--

DROP TABLE IF EXISTS `estore_user_item`;
CREATE TABLE IF NOT EXISTS `estore_user_item` (
`index` int(11) NOT NULL,
  `estore_user_index` int(11) NOT NULL,
  `estore_item_index` int(11) NOT NULL,
  `acquire_timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `acquire_method` enum('shop','trade','gift','admin') NOT NULL DEFAULT 'shop'
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

--
-- Indizes der exportierten Tabellen
--

--
-- Indizes für die Tabelle `estore_banking`
--
ALTER TABLE `estore_banking`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `estore_user_index` (`estore_user_index`);

--
-- Indizes für die Tabelle `estore_category`
--
ALTER TABLE `estore_category`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `name` (`name`);

--
-- Indizes für die Tabelle `estore_item`
--
ALTER TABLE `estore_item`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `name` (`name`), ADD KEY `estore_category_index` (`estore_category_index`);

--
-- Indizes für die Tabelle `estore_right_group`
--
ALTER TABLE `estore_right_group`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `name` (`name`), ADD UNIQUE KEY `flag` (`flag`);

--
-- Indizes für die Tabelle `estore_user`
--
ALTER TABLE `estore_user`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `steam_id64` (`steam_id`), ADD KEY `estore_right_group_index` (`estore_right_group_index`);

--
-- Indizes für die Tabelle `estore_user_history`
--
ALTER TABLE `estore_user_history`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `estore_user_index` (`estore_user_index`,`date`);

--
-- Indizes für die Tabelle `estore_user_item`
--
ALTER TABLE `estore_user_item`
 ADD PRIMARY KEY (`index`), ADD UNIQUE KEY `estore_user_index_2` (`estore_user_index`,`estore_item_index`), ADD KEY `estore_user_index` (`estore_user_index`), ADD KEY `estore_item_index` (`estore_item_index`);

--
-- AUTO_INCREMENT für exportierte Tabellen
--

--
-- AUTO_INCREMENT für Tabelle `estore_banking`
--
ALTER TABLE `estore_banking`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=4;
--
-- AUTO_INCREMENT für Tabelle `estore_category`
--
ALTER TABLE `estore_category`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=2;
--
-- AUTO_INCREMENT für Tabelle `estore_item`
--
ALTER TABLE `estore_item`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=5;
--
-- AUTO_INCREMENT für Tabelle `estore_right_group`
--
ALTER TABLE `estore_right_group`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=3;
--
-- AUTO_INCREMENT für Tabelle `estore_user`
--
ALTER TABLE `estore_user`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=4;
--
-- AUTO_INCREMENT für Tabelle `estore_user_history`
--
ALTER TABLE `estore_user_history`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=4;
--
-- AUTO_INCREMENT für Tabelle `estore_user_item`
--
ALTER TABLE `estore_user_item`
MODIFY `index` int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=2;
--
-- Constraints der exportierten Tabellen
--

--
-- Constraints der Tabelle `estore_banking`
--
ALTER TABLE `estore_banking`
ADD CONSTRAINT `estore_banking_ibfk_1` FOREIGN KEY (`estore_user_index`) REFERENCES `estore_user` (`index`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints der Tabelle `estore_item`
--
ALTER TABLE `estore_item`
ADD CONSTRAINT `estore_item_ibfk_1` FOREIGN KEY (`estore_category_index`) REFERENCES `estore_category` (`index`) ON UPDATE CASCADE;

--
-- Constraints der Tabelle `estore_user`
--
ALTER TABLE `estore_user`
ADD CONSTRAINT `estore_user_ibfk_1` FOREIGN KEY (`estore_right_group_index`) REFERENCES `estore_right_group` (`index`) ON UPDATE CASCADE;

--
-- Constraints der Tabelle `estore_user_history`
--
ALTER TABLE `estore_user_history`
ADD CONSTRAINT `estore_user_history_ibfk_1` FOREIGN KEY (`estore_user_index`) REFERENCES `estore_user` (`index`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints der Tabelle `estore_user_item`
--
ALTER TABLE `estore_user_item`
ADD CONSTRAINT `estore_user_item_ibfk_1` FOREIGN KEY (`estore_user_index`) REFERENCES `estore_user` (`index`) ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT `estore_user_item_ibfk_2` FOREIGN KEY (`estore_item_index`) REFERENCES `estore_item` (`index`) ON DELETE CASCADE ON UPDATE CASCADE;

DELIMITER $$
--
-- Ereignisse
--
DROP EVENT `event_procedure_estore_user_item_delete_expired`$$
CREATE DEFINER=`scripter`@`%` EVENT `event_procedure_estore_user_item_delete_expired` ON SCHEDULE EVERY 1 MINUTE STARTS '2017-03-01 00:00:00' ON COMPLETION PRESERVE ENABLE DO BEGIN
CALL `procedure_estore_user_item_delete_expired`();
END$$

DELIMITER ;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
